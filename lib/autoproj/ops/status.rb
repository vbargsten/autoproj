module Autoproj
    module Ops
        class Status
            Result = Struct.new :uncommitted, :local, :remote do
                def |(r)
                    Result.new(
                        uncommitted || r.uncommitted,
                        local || r.local,
                        remote || r.remote)
                end
            end

            def self.color(*args)
                Autoproj.color(*args)
            end

            def self.handle_package_status(pkg, result, in_sync, only_local)
                pkg_name = pkg.autoproj_name

                if !pkg.importer
                    return [color("  is a local-only package (no VCS)", :bold, :red)]
                elsif !pkg.importer.respond_to?(:status)
                    return [color("  the #{pkg.importer.class.name.gsub(/.*::/, '')} importer does not support status display", :bold, :red)]
                elsif !File.directory?(pkg.srcdir)
                    return [color("  is not imported yet", :magenta)]
                end

                begin
                    status = pkg.importer.status(pkg, only_local)
                rescue Interrupt
                    raise
                rescue Exception
                    return [color("  failed to fetch status information", :red)]
                end

                lines = Array.new

                if status.uncommitted_code
                    lines << color("  contains uncommitted modifications", :red)
                    result.uncommitted = true
                end

                case status.status
                when Autobuild::Importer::Status::UP_TO_DATE
                    in_sync << pkg_name
                    return lines
                when Autobuild::Importer::Status::ADVANCED
                    result.local = true
                    lines << color("  local contains #{status.local_commits.size} commit that remote does not have:", :blue)
                    lines += status.local_commits.map do |line|
                        color("    #{line}", :blue)
                    end
                    return lines
                when Autobuild::Importer::Status::SIMPLE_UPDATE
                    result.remote = true
                    lines << color("  remote contains #{status.remote_commits.size} commit that local does not have:", :magenta)
                    lines += status.remote_commits.map do |line|
                        color("    #{line}", :magenta)
                    end
                    return lines
                when Autobuild::Importer::Status::NEEDS_MERGE
                    result.local  = true
                    result.remote = true
                    lines << "  local and remote have diverged with respectively #{status.local_commits.size} and #{status.remote_commits.size} commits each"
                    lines << color("  -- local commits --", :blue)
                    lines += status.local_commits.map do |line|
                        color("   #{line}", :blue)
                    end
                    lines << color("  -- remote commits --", :magenta)
                    lines += status.remote_commits.map do |line|
                        color("   #{line}", :magenta)
                    end
                    return lines
                end
            end

            def self.display_status(packages, options = Hash.new)
                options = Kernel.validate_options options,
                    only_local: false

                result = Result.new

                in_sync = []
                packages.each do |pkg|
                    lines = handle_package_status(pkg, result, in_sync, options[:only_local])

                    sync_msg = in_sync.join(", ")
                    sync_needs_flush = (in_sync.size > 1 && sync_msg.size > 80)
                    if !lines.empty? && !in_sync.empty?
                        Autoproj.message("#{sync_msg}: #{color("local and remote are in sync", :green)}")
                        in_sync.clear
                    elsif sync_needs_flush
                        package_names, in_sync = in_sync, [in_sync.pop]
                        Autoproj.message(package_names.join(", ") + ",")
                    end

                    pkg_name = pkg.autoproj_name
                    if lines.size == 1
                        Autoproj.message "#{pkg_name}: #{lines.first}"
                    elsif !lines.empty?
                        Autoproj.message "#{pkg_name}:"
                        lines.each do |l|
                            Autoproj.message l
                        end
                    end
                end
                result
            end

            def self.run(cli, user_selection, options = Hash.new)
                cli.silent do
                    cli.initialize_and_load(user_selection)
                end

                options = Kernel.validate_options options,
                    config: nil,
                    local: false

                do_config =
                    if options[:config].nil?
                        user_selection.empty? || cli.config_selected?
                    else
                        options[:config]
                    end



                package_sets_result = Result.new
                if do_config
                    pkg_sets = cli.manifest.each_package_set.
                        map(&:create_autobuild_package)
                    if !pkg_sets.empty?
                        Autoproj.message("autoproj: displaying status of configuration", :bold)
                        package_sets_result = display_status(
                            pkg_sets,
                            only_local: options[:local])
                        Autoproj.message ""
                    end
                end

                Autoproj.message("autoproj: displaying status of packages", :bold)
                packages = cli.resolved_selection.packages.sort.map do |pkg_name|
                    cli.manifest.find_autobuild_package(pkg_name)
                end
                package_result = display_status(
                    packages,
                    only_local: options[:local])

                package_sets_result | package_result
            end
        end
    end
end

