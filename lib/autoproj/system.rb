module Autoproj
    class UserError < RuntimeError; end

    # OS-independent creation of symbolic links. Note that on windows, it only
    # works for directories
    def self.create_symlink(from, to)
        if Autobuild.windows?
            Dir.create_junction(to, from)
        else
            FileUtils.ln_sf from, to
        end
    end

    def self.in_autoproj_installation?(path)
        setup.in_autoproj_installation?(path)
    end

    def self.root_dir=(dir)
        setup.root_dir = dir
    end

    def self.root_dir(dir = Dir.pwd)
        if setup.root_dir
            return setup.root_dir
        end
        Ops::Setup.find_root_dir(dir)
    end

    def self.config_dir
        setup.config_dir
    end

    def self.find_in_path(name)
        if path = Autobuild.find_in_path(name)
            return path
        else raise ArgumentError, "cannot find #{name} in PATH (#{ENV['PATH']})"
        end
    end

    def self.prefix
        setup.prefix_dir
    end

    def self.prefix=(new_path)
        setup.prefix_dir
    end

    def self.build_dir
        setup.build_dir
    end

    def self.config_file(file)
        setup.config_file(file)
    end

    def self.run_as_user(*args)
        setup.run_as_user(*args)
    end

    def self.run_as_root(*args)
        setup.run_as_root(*args)
    end

    def self.remotes_dir
        setup.remotes_dir
    end

    def self.env_inherit(*names)
        Autobuild.env_inherit(*names)
    end

    # @deprecated use isolate_environment instead
    def self.set_initial_env
        isolate_environment
    end

    def self.isolate_environment
        setup.isolate_environment
    end

    def self.prepare_environment
        setup.prepare_environment
    end

    def self.shell_helpers=(value)
        config.shell_helpers = value
    end
    def self.shell_helpers?
        config.shell_helpers?
    end

    def self.load(package_set, *path)
        setup.load(package_set, *path)
    end

    def self.load_if_present(package_set, *path)
        setup.load_if_present(package_set, *path)
    end

    # Create the env.sh script in +subdir+. In general, +subdir+ should be nil.
    def self.export_env_sh(subdir = nil)
        # Make sure that we have as much environment as possible
        Autoproj::CmdLine.update_environment

        filename = if subdir
               File.join(Autoproj.root_dir, subdir, ENV_FILENAME)
           else
               File.join(Autoproj.root_dir, ENV_FILENAME)
           end

        shell_dir = File.expand_path(File.join("..", "..", "shell"), File.dirname(__FILE__))
        if Autoproj.shell_helpers?
            Autoproj.message "sourcing autoproj shell helpers"
            Autoproj.message "add \"Autoproj.shell_helpers = false\" in autoproj/init.rb to disable"
            Autobuild.env_source_after(File.join(shell_dir, "autoproj_sh"))
        end

        File.open(filename, "w") do |io|
            if Autobuild.env_inherit
                io.write <<-EOF
                if test -n "$AUTOPROJ_CURRENT_ROOT" && test "$AUTOPROJ_CURRENT_ROOT" != "#{Autoproj.root_dir}"; then
                    echo "the env.sh from $AUTOPROJ_CURRENT_ROOT is already loaded. Start a new shell before sourcing this one"
                    return
                fi
                EOF
            end
            Autobuild.export_env_sh(io)
        end
    end

    # Look into +dir+, searching for shared libraries. For each library, display
    # a warning message if this library has undefined symbols.
    def self.validate_solib_dependencies(dir, exclude_paths = [])
        Find.find(File.expand_path(dir)) do |name|
            next unless name =~ /\.so$/
            next if exclude_paths.find { |p| name =~ p }

            output = `ldd -r #{name} 2>&1`
            if output =~ /undefined symbol/
                Autoproj.message("  WARN: #{name} has undefined symbols", :magenta)
            end
        end
    end
end

