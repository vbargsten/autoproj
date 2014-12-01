module Autoproj
    module Ops
        # Operations related to building packages
        #
        # Note that these do not perform import or osdeps installation. It is
        # assumed that the packages that should be built have been cleanly
        # imported
        class Build
            # The manifest on which we operate
            # @return [Manifest]
            attr_reader :manifest

            def initialize(manifest)
                @manifest = manifest
            end

            # Triggers a rebuild of all packages
            #
            # It rebuilds (i.e. does a clean + build) of all packages declared
            # in the manifest's layout. It also performs a reinstall of all
            # non-OS-specific managers that support it (e.g. RubyGems) if
            # {update_os_dependencies?} is set to true (the default)
            def rebuild_all
                packages = manifest.all_layout_packages
                rebuild_packages(packages, packages)
            end

            # Triggers a rebuild of a subset of all packages
            #
            # @param [Array<String>] selected_packages the list of package names
            #   that should be rebuilt
            # @param [Array<String>] all_enabled_packages the list of package names
            #   for which a build should be triggered (usually selected_packages
            #   plus dependencies)
            # @return [void]
            def rebuild_packages(selected_packages, all_enabled_packages)
                selected_packages.each do |pkg_name|
                    manifest.find_autobuild_package(pkg_name).prepare_for_rebuild
                end
                build_packages(all_enabled_packages)
            end

            # Triggers a force-build of all packages
            #
            # Unlike a rebuild, a force-build forces the package to go through
            # all build steps (even if they are not needed) but does not clean
            # the current build byproducts beforehand
            #
            def force_build_all
                packages = manifest.all_layout_packages
                rebuild_packages(packages, packages)
            end

            # Triggers a force-build of a subset of all packages
            #
            # Unlike a rebuild, a force-build forces the package to go through
            # all build steps (even if they are not needed) but does not clean
            # the current build byproducts beforehand
            #
            # This method force-builds of all packages declared
            # in the manifest's layout
            #
            # @param [Array<String>] selected_packages the list of package names
            #   that should be rebuilt
            # @param [Array<String>] all_enabled_packages the list of package names
            #   for which a build should be triggered (usually selected_packages
            #   plus dependencies)
            # @return [void]
            def force_build_packages(selected_packages, all_enabled_packages)
                selected_packages.each do |pkg_name|
                    manifest.find_autobuild_package(pkg_name).prepare_for_forced_build
                end
                build_packages(all_enabled_packages)
            end

            # Builds the listed packages
            #
            # Only build steps that are actually needed will be performed. See
            # {force_build_packages} and {rebuild_packages} to override this
            #
            # @param [Array<String>] all_enabled_packages the list of package
            #   names of the packages that should be rebuilt
            # @return [void]
            def build_packages(all_enabled_packages)
                Autobuild.do_rebuild = false
                Autobuild.do_forced_build = false
                Autobuild.apply(all_enabled_packages, "autoproj-build", ['build'])
            end

            # CLI handling for autoproj build
            def self.run(cli, user_selection, options = Hash.new)
                enabled_packages, options = cli.common_setup(user_selection, options)
                if !options[:deps]
                    enabled_packages.each do |pkg_name|
                        if !cli.resolved_selection.include?(pkg_name)
                            manifest.find_autobuild_package(pkg_name).disable
                        end
                    end
                    enabled_packages = cli.resolved_selection.packages
                end

                # Note: --rebuild supersedes --force
                build_mode =
                    if options[:rebuild] then :rebuild
                    elsif options[:force] then :force
                    else :incremental
                    end

                if build_mode == :rebuild && user_selection.empty?
                    opt = BuildOption.new(
                        "", "boolean",
                        {doc: ["this is going to trigger a #{mode_name} of all packages.",
                               "Is that really what you want ?"]}, nil)
                    if !opt.ask(false)
                        exit
                    end
                end

                ops = Ops::Build.new(manifest)
                if mode == :incremental
                    ops.build_packages(enabled_packages)
                elsif mode == :force
                    ops.force_build_packages(enabled_packages)
                elsif mode == :rebuild
                    if user_selection.empty?
                        manifest.pristine_os_dependencies(enabled_packages)
                    end
                    ops.rebuild_packages(enabled_packages)
                end
            end
        end
    end
end
