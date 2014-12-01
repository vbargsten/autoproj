require 'autoproj/ops/user_selection'
module Autoproj
    module CLI
        module Base
            include Ops::UserSelection

            attr_reader :setup

            def manifest
                setup.manifest
            end

            def osdeps
                setup.manifest.osdeps
            end

            attr_reader :user_selection

            attr_reader :resolved_selection

            def initialize(*args)
                @setup = Autoproj.setup = Ops::Setup.new
                setup.base_setup
                super
            end

            # Initialize the autoproj layer and load the configuration
            def initialize_and_load(user_selection, options = Hash.new)
                import_options, options = Kernel.filter_options options,
                    update_from: nil,
                    only_local: false,
                    checkout: false,
                    only_checkout: true
                selection_options, options = Kernel.filter_options options,
                    select_all_matches: false,
                    filter: true
                options = Kernel.validate_options options,
                    update_myself: false
                update_myself = options[:update_myself]

                @user_selection, @config_selected =
                    resolve_paths_in_argv(user_selection)

                initialize_osdeps
                if update_myself
                    setup.update_myself
                end

                Ops.update_configuration(setup, import_options)

                setup.load_configuration
                setup.setup_all_package_directories
                resolve_user_selection(user_selection, selection_options)
                setup.finalize_package_setup
                @resolved_selection =
                    resolve_user_selection(user_selection, selection_options)
                validate_user_selection(user_selection, resolved_selection)
            end

            def initialize_osdeps
                # Define the option NOW, as update_os_dependencies? needs to know in
                # what mode we are.
                #
                # It might lead to having multiple operating system detections, but
                # that's the best I can do for now.
                Autoproj::OSDependencies.define_osdeps_mode_option
                osdeps.osdeps_mode

                # Do that AFTER we have properly setup Autoproj.osdeps as to avoid
                # unnecessarily redetecting the operating system
                setup.config.set('operating_system',
                                 Autoproj::OSDependencies.operating_system(force: true),
                                 true)
            end

            def handle_common_options(options)
                options, remaining = Kernel.filter_options options,
                    verbose: false,
                    debug: false,
                    color: true,
                    progress: true
                if options[:verbose]
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = false
                    Autobuild.debug = false
                end
                if options[:debug]
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = true
                    Autobuild.debug = true
                end
                if !options[:color].nil?
                    Autoproj::CmdLine.color = 
                        Autobuild.color = options[:color]
                end
                if !options[:progress].nil?
                    Autobuild.progress_display_enabled = options[:progress]
                end
                remaining
            end

            def common_setup(user_selection, options = Hash.new)
                options = handle_common_options(options)
                if !options[:osdeps]
                    osdeps.osdeps_mode = []
                end
                initialize_and_load(
                    user_selection,
                    update_myself: false,
                    checkout: options[:checkout],
                    only_checkout: true)

                enabled_packages = Ops.import_packages(
                    manifest,
                    resolved_selection,
                    checkout: options[:checkout],
                    only_checkout: true)
                return enabled_packages, options
            end

            def silent(&block)
                Autoproj.silent(&block)
            end

            def report(options = Hash.new)
                Autobuild::Reporting.report do
                    yield
                end
                if !options[:silent]
                    Autobuild::Reporting.success
                end

            rescue ConfigError => e
                STDERR.puts
                STDERR.puts Autoproj.color(e.message, :red, :bold)
                if Ops::Setup.in_autoproj_installation?(Dir.pwd)
                    root_dir = /#{Regexp.quote(Autoproj.root_dir)}(?!\/\.gems)/
                    e.backtrace.find_all { |path| path =~ root_dir }.
                        each do |path|
                            STDERR.puts Autoproj.color("  in #{path}", :red, :bold)
                        end
                end
                if Autobuild.debug then raise
                else exit 1
                end
            rescue Interrupt
                STDERR.puts
                STDERR.puts Autoproj.color("Interrupted by user", :red, :bold)
                if Autobuild.debug then raise
                else exit 1
                end
            end

            def resolve_paths_in_argv(argv)
                argv = argv.map do |arg|
                    if File.directory?(arg)
                        File.expand_path(arg)
                    else arg
                    end
                end

                needs_update_config = false
                argv.delete_if do |name|
                    if name =~ /^#{Regexp.quote(Autoproj.config_dir + File::SEPARATOR)}/ ||
                        name =~ /^#{Regexp.quote(Autoproj.remotes_dir + File::SEPARATOR)}/
                        needs_update_config = true
                    elsif (Autoproj.config_dir + File::SEPARATOR) =~ /^#{Regexp.quote(name)}/
                        needs_update_config = true
                        false
                    end
                end

                return argv, needs_update_config
            end
        end
    end
end

