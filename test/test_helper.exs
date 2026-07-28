Magma.TestRepo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Magma.TestRepo, :manual)

{:ok, _pid} = Magma.Test.Effects.start_link()
{:ok, _registry} = Registry.start_link(keys: :duplicate, name: Magma.Notifier)
{:ok, _oban} = Oban.start_link(Application.fetch_env!(:magma, Oban))

ExUnit.start()
