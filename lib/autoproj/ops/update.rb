module Autoproj
    module Ops
        class Update
            # CLI handling for autoproj update
            def self.run(cli, user_selection, options)
                if !options[:osdeps]
                    cli.osdeps.osdeps_mode = []
                end
                _, config_selected = cli.resolve_paths_in_argv(user_selection)
                update_config =
                    if options[:config].nil?
                        user_selection.empty? || config_selected
                    else options[:config]
                    end

                cli.initialize_and_load(
                    user_selection,
                    update_myself: options[:osdeps] && user_selection.empty?,
                    only_checkout: options[:checkout] || !update_config,
                    only_local: options[:local],
                    update_from: options[:from])

                import_packages = Ops::PackageImport.new(
                    cli.manifest,
                    only_checkout: options[:checkout],
                    only_local: options[:local],
                    update_from: options[:from])
                if !options[:deps]
                    cli.resolved_selection.each do |pkg_name|
                        import_packages.import_single_package(pkg_name)
                    end
                else
                    import_packages.import_packages(cli.resolved_selection)
                end
            end
        end
    end
end

