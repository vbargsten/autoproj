if RUBY_VERSION < "1.9.2"
    STDERR.puts "autoproj requires Ruby >= 1.9.2"
    exit 1
end

require 'thor'
require 'autoproj'
require 'autoproj/autobuild'
require 'autoproj/cli/base'

module Autoproj
    module CLI
        class Main < Thor
            include CLI::Base

            class_option 'verbose',
                desc: 'display additional progress information, including the commands that are being executed'
            class_option 'debug',
                desc: 'like --verbose, but display dependency resolution and Rake trace information'
            class_option 'color', type: :boolean,
                desc: 'use color in the output'
            class_option 'progress', type: :boolean,
                desc: 'display progress information'

            desc 'build [PACKAGES]', "performs a build of all packages that need it"
            option :force, aliases: 'f',
                desc: "force building from the first build phase (usually configuration)"
            option "rebuild",
                desc: "rebuilds the package from scratch, and optionally its dependencies"
            option 'deps', type: :boolean,
                desc: 'handle only the packages listed on the command line and not their dependencies'
            option 'osdeps', type: :boolean,
                desc: 'installs the OS dependencies that are missing (default is yes)'
            option "nice", type: :numeric,
                desc: "the priority at which the build processes should run (0 is highest and 19 is lowest)"
            def build(*user_selection)
                require 'autoproj/ops/build'
                options = handle_common_options(self.options)
                report do
                    Ops::Build.run(self, user_selection, options)
                end
            end

            desc 'update [PACKAGES]', "updates the given packages and their dependencies"
            option 'from DIR',
                desc: "get all updates from the autoproj project currently checked out at DIR"
            option 'deps', type: :boolean,
                desc: 'update only the packages listed on the command line and not their dependencies'
            option 'config', type: :boolean,
                desc: 'update the autoproj configuration as well (default if the configuration directory is given on the command line or if no arguments are given)'
            option 'checkout', aliases: '-c', type: :boolean,
                desc: 'only checkout packages that are not there, do not update'
            option 'keep-going', aliases: '-k', type: :boolean,
                desc: 'do not stop on error'
            option "osdeps", type: :boolean,
                desc: "disable osdeps handling"
            option "local",
                desc: "only use local information to update for importers that support it"
            option 'nice NICE', type: :numeric,
                desc: 'nice the subprocesses to the given value'
            def update(*user_selection)
                require 'autoproj/ops/update'
                options = handle_common_options(self.options)
                report do
                    Ops::Update.run(self, user_selection, options)
                end
            end

            desc 'show [PACKAGES]', 'displays information about the given packages. Without arguments, shows all'
            def show(*user_selection)
                require 'autoproj/ops/show'
                options = handle_common_options(self.options)
                report(silent: true) do
                    Ops::Show.run(self, user_selection, options)
                end
            end

            desc 'status [PACKAGES]', 'display synchronization information between the currently checked out packages and their remote version control system'
            option 'exit-code', type: :boolean,
                desc: 'exits with a code that reflects the overall project status'
            option 'config', type: :boolean,
                desc: 'display the information about the configuration repositories as well (default if the configuration directory is given on the command line or if no arguments are given)'
            option "local",
                desc: "only use local information for importers that support it"
            def status(*user_selection)
                require 'autoproj/ops/status'
                options = handle_common_options(self.options)

                exit_code, options = Kernel.filter_options options,
                    exit_code: false
                exit_code = exit_code[:exit_code]
                report(silent: true) do
                    result = Ops::Status.run(self, user_selection, options)
                    if exit_code
                        code = 0
                        if result.uncommitted
                            code |= 1
                        end
                        if result.local
                            code |= 2
                        end
                        if result.remote
                            code |= 4
                        end
                        exit(code)
                    else
                        exit(0)
                    end
                end
            end
        end
    end
end

