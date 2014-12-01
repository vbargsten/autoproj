module Autoproj
    module Ops
    module Tools
        # Data structure used to use autobuild importers without a package, to
        # import configuration data.
        #
        # It has to match the interface of Autobuild::Package that is relevant
        # for importers
        class FakePackage < Autobuild::Package
            attr_reader :srcdir
            attr_reader :importer

            # Used by the autobuild importers
            attr_accessor :updated

            def autoproj_name
                name
            end

            def initialize(text_name, srcdir, importer = nil)
                super(text_name)
                @srcdir = srcdir
                @importer = importer
                @@packages.delete(text_name)
            end

            def import(only_local = false)
                importer.import(self, only_local)
            end

            def add_stat(*args)
            end
        end

        # Creates an autobuild package whose job is to allow the import of a
        # specific repository into a given directory.
        #
        # +vcs+ is the VCSDefinition file describing the repository, +text_name+
        # the name used when displaying the import progress, +pkg_name+ the
        # internal name used to represent the package and +into+ the directory
        # in which the package should be checked out.
        def create_autobuild_package(vcs, text_name, into)
            importer     = vcs.create_autobuild_importer
            FakePackage.new(text_name, into, importer)

        rescue Autobuild::ConfigException => e
            raise ConfigError.new, "cannot import #{text_name}: #{e.message}", e.backtrace
        end

        def load_autoprojrc
            # Load the user-wide autoproj RC file
            if home_dir = Dir.home
                rcfile = File.join(home_dir, '.autoprojrc')
                if File.file?(rcfile)
                    Kernel.load rcfile
                end
            end
        end

        def common_options(parser)
            parser.on '--verbose' do
                Autoproj.verbose  = true
                Autobuild.verbose = true
                Rake.application.options.trace = false
                Autobuild.debug = false
            end

            parser.on '--debug' do
                Autoproj.verbose  = true
                Autobuild.verbose = true
                Rake.application.options.trace = true
                Autobuild.debug = true
            end

            parser.on("--[no-]color", "enable or disable color in status messages (enabled by default)") do |flag|
                Autoproj::CmdLine.color = flag
                Autobuild.color = flag
            end

            parser.on("--[no-]progress", "enable or disable progress display (enabled by default)") do |flag|
                Autobuild.progress_display_enabled = flag
            end
        end

        def mail_options(opts)
            mail_config = Hash.new
            opts.on("--mail-from EMAIL", String, "From: field of the sent mails") do |from_email|
                mail_config[:from] = from_email
            end
            opts.on("--mail-to EMAILS", String, "comma-separated list of emails to which the reports should be sent") do |emails| 
                mail_config[:to] ||= []
                mail_config[:to] += emails.split(',')
            end
            opts.on("--mail-subject SUBJECT", String, "Subject: field of the sent mails") do |subject_email|
                mail_config[:subject] = subject_email
            end
            opts.on("--mail-smtp HOSTNAME", String, " address of the mail server written as hostname[:port]") do |smtp|
                raise "invalid SMTP specification #{smtp}" unless smtp =~ /^([^:]+)(?::(\d+))?$/
                mail_config[:smtp] = $1
                mail_config[:port] = Integer($2) if $2 && !$2.empty?
            end
            opts.on("--mail-only-errors", "send mail only on errors") do
                mail_config[:only_errors] = true
            end
            mail_config
        end

        def common_acting_commands_options(opts)
            common_options(opts)
        end

        def build_update_options(opts)
            common_acting_commands_options(opts)
        end

        def display_newest_files
            fields = []
            Rake::Task.tasks.each do |task|
                if task.kind_of?(Autobuild::SourceTreeTask)
                    task.timestamp
                    fields << ["#{task.name}:", task.newest_file, task.newest_time.to_s]
                end
            end

            field_sizes = fields.inject([0, 0, 0]) do |sizes, line|
                3.times do |i|
                    sizes[i] = [sizes[i], line[i].length].max
                end
                sizes
            end
            format = "  %-#{field_sizes[0]}s %-#{field_sizes[1]}s at %-#{field_sizes[2]}s"
            fields.each do |line|
                Autoproj.message(format % line)
            end
        end


        def update_environment(manifest)
            manifest.reused_installations.each do |reused_manifest|
                reused_manifest.each_autobuild_package do |pkg|
                    pkg.update_environment
                end
            end

            # Make sure that we have the environment of all selected packages
            manifest.all_selected_packages(false).each do |pkg_name|
                manifest.find_package(pkg_name).autobuild.update_environment
            end
        end

        # Run the provided command as user
        def run_as_user(*args)
            if !system(*args)
                raise "failed to run #{args.join(" ")}"
            end
        end
        
        # Run the provided command as root, using sudo to gain root access
        def run_as_root(*args)
            if !system(Autobuild.tool_in_path('sudo'), *args)
                raise "failed to run #{args.join(" ")} as root"
            end
        end

        extend Tools
    end
    end
end

