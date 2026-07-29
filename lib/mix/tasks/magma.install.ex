if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Magma.Install do
    @moduledoc """
    Writes magma's four resources into your application and points magma at them.

        mix igniter.install magma

    The resources land in a domain of your own — `--domain` names one, and without it they go
    in `YourApp.Magma`, which is created if it is missing. They are ordinary source files, so
    adding a policy or an attribute later is an edit rather than an escape hatch.
    """
    @shortdoc "Installs magma: four resources, a domain, and the config pointing at them."

    use Igniter.Mix.Task

    @roles [
      {"Workflow", Magma.Resource.Workflow, "magma_workflows"},
      {"Checkpoint", Magma.Resource.Checkpoint, "magma_checkpoints"},
      {"Signal", Magma.Resource.Signal, "magma_signals"},
      {"Waiter", Magma.Resource.Waiter, "magma_waiters"}
    ]

    @impl true
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :magma,
        schema: [yes: :boolean, repo: :string, domain: :string],
        aliases: [y: :yes, r: :repo, d: :domain],
        composes: ["ash_postgres.install"]
      }
    end

    @impl true
    def igniter(igniter) do
      opts = igniter.args.options
      {igniter, repo} = AshPostgres.Igniter.select_repo(igniter, generate?: true)
      domain = domain_module(igniter, opts)
      workflow = Module.concat(domain, Workflow)

      {existing?, igniter} = Igniter.Project.Module.module_exists(igniter, domain)

      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_postgres)
      |> create_resources(domain, workflow, repo)
      |> create_domain(domain)
      |> reference_resources(domain, existing?)
      |> configure(domain, repo)
      |> Ash.Igniter.codegen("add_magma_resources")
    end

    defp domain_module(igniter, opts) do
      case opts[:domain] do
        nil -> Igniter.Project.Module.module_name(igniter, "Magma")
        domain -> Igniter.Project.Module.parse(domain)
      end
    end

    defp create_resources(igniter, domain, workflow, repo) do
      Enum.reduce(@roles, igniter, fn {name, extension, table}, igniter ->
        module = Module.concat(domain, name)

        # Find-or-create, so running the installer again leaves a resource you have since
        # edited exactly as it is.
        Igniter.Project.Module.find_and_update_or_create_module(
          igniter,
          module,
          resource_body(domain, extension, table, repo, workflow, module == workflow),
          fn zipper -> {:ok, zipper} end
        )
      end)
    end

    defp resource_body(domain, extension, table, repo, workflow, is_workflow?) do
      """
      use Ash.Resource,
        domain: #{inspect(domain)},
        data_layer: AshPostgres.DataLayer,
        extensions: [#{inspect(extension)}]

      #{unless is_workflow?, do: workflow_section(workflow)}
      postgres do
        table "#{table}"
        repo #{inspect(repo)}
      end
      """
    end

    defp workflow_section(workflow) do
      """
      magma do
        workflow #{inspect(workflow)}
      end
      """
    end

    defp create_domain(igniter, domain) do
      Igniter.Project.Module.find_and_update_or_create_module(
        igniter,
        domain,
        """
        use Ash.Domain

        resources do
        end
        """,
        fn zipper -> {:ok, zipper} end
      )
    end

    # A domain that was already here has its own resource list, and adding to it again would
    # only repeat what is in it.
    defp reference_resources(igniter, _domain, true), do: igniter

    defp reference_resources(igniter, domain, false) do
      Enum.reduce(@roles, igniter, fn {name, _extension, _table}, igniter ->
        Ash.Domain.Igniter.add_resource_reference(igniter, domain, Module.concat(domain, name))
      end)
    end

    defp configure(igniter, domain, repo) do
      app_name = Igniter.Project.Application.app_name(igniter)

      igniter
      |> Igniter.Project.Config.configure("config.exs", :magma, [:domain], domain)
      |> Igniter.Project.Config.configure("config.exs", :magma, [:repo], repo)
      |> Igniter.Project.Config.configure("config.exs", app_name, [:ash_domains], [domain],
        updater: &Igniter.Code.List.prepend_new_to_list(&1, domain)
      )
    end
  end
end
