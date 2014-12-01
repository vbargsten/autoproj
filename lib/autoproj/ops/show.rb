module Autoproj
    module Ops
        class Show
            attr_reader :manifest
            attr_reader :revdeps
            attr_reader :default_packages

            def initialize(manifest)
                @manifest = manifest
                @revdeps = manifest.compute_revdeps
                @default_packages = manifest.default_packages
            end

            def find_selection_path(from, to)
                path = [from]
                if from == to
                    return path
                end

                manifest.resolve_package_set(from).each do |pkg_name|
                    manifest.find_autobuild_package(pkg_name).dependencies.each do |dep_pkg_name|
                        if result = find_selection_path(dep_pkg_name, to)
                            return path + result
                        end
                    end
                end
                nil
            end

            def vcs_to_array(vcs)
                if vcs.kind_of?(Hash)
                    options = vcs.dup
                    type = options.delete('type')
                    url  = options.delete('url')
                else 
                    options = vcs.options
                    type = vcs.type
                    url = vcs.url
                end

                value = []
                if type
                    value << ['type', type]
                end
                if url
                    value << ['url', url]
                end
                value = value.concat(options.to_a.sort_by { |k, _| k.to_s })
                value.map do |key, value|
                    if value.respond_to?(:to_str) && File.file?(value) && value =~ /^\//
                        value = Pathname.new(value).relative_path_from(Pathname.new(Autoproj.root_dir))
                    end
                    [key, value]
                end
            end

            def display_package_info(package_name)
                result = manifest.resolve_package_name(package_name, :filter => false)
                packages, osdeps = result.partition { |type, name| type == :package }
                packages = packages.map(&:last)
                osdeps   = osdeps.map(&:last)

                packages.each do |pkg_name|
                    puts Autoproj.color("source package #{pkg_name}", :bold)
                    puts "  source definition"
                    vcs = manifest.importer_definition_for(pkg_name)

                    fragments = []
                    if vcs.raw
                        first = true
                        fragments << [nil, vcs_to_array(vcs)]
                        vcs.raw.each do |pkg_set, vcs_info|
                            title = if first
                                        "first match: in #{pkg_set}"
                                    else "overriden in #{pkg_set}"
                                    end
                            first = false
                            fragments << [title, vcs_to_array(vcs_info)]
                        end
                    end
                    fragments.each do |title, elements|
                        if title
                            puts "    #{title}"
                            elements.each do |key, value|
                                puts "      #{key}: #{value}"
                            end
                        else
                            elements.each do |key, value|
                                puts "    #{key}: #{value}"
                            end
                        end
                    end

                    if default_packages.include?(pkg_name)
                        selection = default_packages.selection[pkg_name]
                        if selection.include?(pkg_name) && selection.size == 1
                            puts "  is directly selected by the manifest"
                        else
                            selection = selection.dup
                            selection.delete(pkg_name)
                            puts "  is directly selected by the manifest via #{selection.to_a.join(", ")}"
                        end
                    else
                        puts "  is not directly selected by the manifest"
                    end
                    if manifest.ignored?(pkg_name)
                        puts "  is ignored"
                    end
                    if manifest.excluded?(pkg_name)
                        puts "  is excluded: #{manifest.exclusion_reason(pkg_name)}"
                    end

                    if !File.directory?(Autobuild::Package[pkg_name].srcdir)
                        puts Autobuild.color("  this package is not checked out yet, the dependency information will probably be incomplete", :magenta)
                    end
                    all_reverse_dependencies = Set.new
                    pkg_revdeps = revdeps[pkg_name].dup.to_a
                    while !pkg_revdeps.empty?
                        parent_name = pkg_revdeps.shift
                        next if all_reverse_dependencies.include?(parent_name)
                        all_reverse_dependencies << parent_name
                        pkg_revdeps.concat(revdeps[parent_name].to_a)
                    end
                    if all_reverse_dependencies.empty?
                        puts "  no reverse dependencies"
                    else
                        puts "  reverse dependencies: #{all_reverse_dependencies.sort.join(", ")}"
                    end

                    selections = Set.new
                    all_reverse_dependencies = all_reverse_dependencies.to_a.sort
                    all_reverse_dependencies.each do |parent_name|
                        if default_packages.include?(parent_name)
                            selections |= default_packages.selection[parent_name]
                        end
                    end

                    if !selections.empty?
                        puts "  selected by way of"
                        selections.each do |root_pkg|
                            path = find_selection_path(root_pkg, pkg_name)
                            puts "    #{path.join(">")}"
                        end
                    end
                    puts "  directly depends on: #{Autobuild::Package[pkg_name].dependencies.sort.join(", ")}"
                end

                osdeps.each do |pkg_name|
                    puts Autoproj.color("the osdep '#{pkg_name}'", :bold)
                    manifest.osdeps.resolve_os_dependencies([pkg_name]).each do |manager, os_packages|
                        puts "  #{manager.names.first}: #{os_packages.map { |*subnames| subnames.join(" ") }.join(", ")}"
                    end
                end
            end

            def self.run(cli, user_selection, options = Hash.new)
                cli.silent do
                    cli.initialize_and_load(user_selection,
                                            select_all_matches: true,
                                            filter: false)
                end
                packages = cli.resolved_selection.packages
                if packages.empty?
                    raise Autobuild::Exception, "no packages or OS packages match #{user_selection.join(" ")}"
                    exit 1
                end

                ops = new(cli.manifest)
                packages.each do |name|
                    ops.display_package_info(name)
                end
            end
        end
    end
end

