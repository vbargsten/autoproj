module Autoproj
    module Ops
        # Handling of package import and loading
        class PackageImport
            # @return [Manifest] the manifest object we're working with
            attr_reader :manifest

            def initialize(manifest)
                @manifest = manifest
            end

            def mark_exclusion_along_revdeps(pkg_name, revdeps, chain = [], reason = nil)
                root = !reason
                chain.unshift pkg_name
                if root
                    reason = manifest.exclusion_reason(pkg_name)
                else
                    if chain.size == 1
                        manifest.add_exclusion(pkg_name, "its dependency #{reason}")
                    else
                        manifest.add_exclusion(pkg_name, "#{reason} (dependency chain: #{chain.join(">")})")
                    end
                end

                return if !revdeps.has_key?(pkg_name)
                revdeps[pkg_name].each do |dep_name|
                    if !manifest.excluded?(dep_name)
                        mark_exclusion_along_revdeps(dep_name, revdeps, chain.dup, reason)
                    end
                end
            end
            
            def import_single_package(selection, options = Hash.new)
                options = Kernel.validate_options options,
                    only_local: false
                only_local = options[:only_local]

                if pkg.respond_to?(:to_str)
                    pkg = Autobuild::Package[pkg]
                    if !pkg
                        raise ArgumentError, "package #{pkg} does not exist"
                    end
                    pkg
                end

                # If the package has no importer, the source directory must
                # be there
                if !pkg.importer && !File.directory?(pkg.srcdir)
                    raise ConfigError.new, "#{pkg.name} has no VCS, but is not checked out in #{pkg.srcdir}"
                end

                ## COMPLETELY BYPASS RAKE HERE
                # The reason is that the ordering of import/prepare between
                # packages is not important BUT the ordering of import vs.
                # prepare in one package IS important: prepare is the method
                # that takes into account dependencies.
                pkg.import(only_local)
                Rake::Task["#{pkg.name}-import"].
                    instance_variable_set(:@already_invoked, true)
                manifest.load_package_manifest(pkg.name)

                # The package setup mechanisms might have added an exclusion
                # on this package. Handle this.
                if manifest.excluded?(pkg.name)
                    return
                end

                Autoproj.each_post_import_block(pkg) do |block|
                    block.call(pkg)
                end
                pkg.update_environment
            end

            def self.import_single_package(manifest, *args, &block)
                new(manifest).import_single_package(*args, &block)
            end

            # Import and load the packages selected in the given selection
            #
            # @param [PackageSelection] selection
            def import_packages(selection, options = Hash.new)
                selected_packages = selection.packages.
                    map do |pkg_name|
                        pkg = Autobuild::Package[pkg_name]
                        if !pkg
                            raise ConfigError.new, "selected package #{pkg_name} does not exist"
                        end
                        pkg
                    end.to_set

                # The set of all packages that are currently selected by +selection+
                all_processed_packages = Set.new
                # The reverse dependencies for the package tree. It is discovered as
                # we go on with the import
                #
                # It only contains strong dependencies. Optional dependencies are
                # not included, as we will use this only to take into account
                # package exclusion (and that does not affect optional dependencies)
                reverse_dependencies = Hash.new { |h, k| h[k] = Set.new }

                package_queue = selected_packages.to_a.sort_by(&:name)
                while !package_queue.empty?
                    pkg = package_queue.shift

                    # Remove packages that have already been processed
                    next if all_processed_packages.include?(pkg.name)
                    all_processed_packages << pkg.name

                    import_single_package(pkg, options)

                    if manifest.excluded?(pkg.name)
                        mark_exclusion_along_revdeps(pkg.name, reverse_dependencies)
                        # Run a filter now, to have errors as early as possible
                        selection.filter_excluded_and_ignored_packages(manifest)
                        # Delete this package from the current_packages set
                        next
                    end

                    pkg_dependencies = resolve_package_dependencies(pkg, reverse_dependencies)
                    package_queue.concat(pkg_dependencies)

                    # Verify that everything is still OK with the new
                    # exclusions/ignores
                    selection.filter_excluded_and_ignored_packages(manifest)
                end

                all_enabled_packages = Set.new
                package_queue = selection.packages.dup
                # Run optional dependency resolution until we have a fixed point
                while !package_queue.empty?
                    pkg_name = package_queue.shift
                    next if all_enabled_packages.include?(pkg_name)
                    all_enabled_packages << pkg_name

                    pkg = Autobuild::Package[pkg_name]
                    pkg.resolve_optional_dependencies

                    pkg.prepare if !pkg.disabled?
                    Rake::Task["#{pkg.name}-prepare"].
                        instance_variable_set(:@already_invoked, true)

                    package_queue.concat(pkg.dependencies)
                end

                if Autoproj.verbose
                    Autoproj.message "autoproj: finished importing packages"
                end

                selection.exclusions.each do |sel, pkg_names|
                    pkg_names.sort.each do |pkg_name|
                        Autoproj.warn "#{pkg_name}, which was selected for #{sel}, cannot be built: #{Autoproj.manifest.exclusion_reason(pkg_name)}", :bold
                    end
                end
                selection.ignores.each do |sel, pkg_names|
                    pkg_names.sort.each do |pkg_name|
                        Autoproj.warn "#{pkg_name}, which was selected for #{sel}, is ignored", :bold
                    end
                end

                return all_enabled_packages
            end

            def self.import_packages(manifest, *args, &block)
                new(manifest).import_packages(*args, &block)
            end

            def resolve_package_dependencies(pkg, reverse_dependencies)
                # Verify that its dependencies are there, and add
                # them to the selected_packages set so that they get
                # imported as well
                new_packages = []
                pkg.dependencies.each do |dep_name|
                    reverse_dependencies[dep_name] << pkg.name
                    new_packages << Autobuild::Package[dep_name]
                end
                pkg_opt_deps, _ = pkg.partition_optional_dependencies
                pkg_opt_deps.each do |dep_name|
                    new_packages << Autobuild::Package[dep_name]
                end

                new_packages.delete_if do |pkg|
                    if manifest.excluded?(pkg.name)
                        mark_exclusion_along_revdeps(pkg.name, reverse_dependencies)
                        true
                    elsif manifest.ignored?(pkg.name)
                        true
                    end
                end
                new_packages.sort_by(&:name)
            end
        end
    end
end

