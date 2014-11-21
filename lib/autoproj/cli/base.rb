module Autoproj
    module CLI
        class Base
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

            attr_reader :enabled_packages

            def initialize
                @setup = Autoproj.setup = Ops::Setup.new
                setup.base_setup
            end

            # Initialize the autoproj layer and load the configuration
            def initialize_and_load(user_selection, options = Hash.new)
                import_options, options = Kernel.filter_options options,
                    :only_checkout, :only_local, :update_from
                options = Kernel.validate_options options,
                    update_myself: false
                update_myself = options[:update_myself]

                @user_selection, @config_selected =
                    Tools.resolve_paths_in_argv(user_selection)

                initialize_osdeps
                if update_myself
                    setup.update_myself
                end

                Ops.update_configuration(setup, import_options)

                setup.load_configuration
                setup.setup_all_package_directories
                resolve_user_selection(user_selection)
                setup.finalize_package_setup
                @resolved_selection =
                    resolve_user_selection(user_selection)
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
        end
    end
end

