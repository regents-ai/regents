defmodule AshPlatformWeb.Showcase.ProductPreviews do
  @moduledoc "Static signed-out compositions, displayed in a scriptless sandboxed iframe."
  def all do
    common = %{
      __changed__: nil,
      myself: nil,
      authenticated: false,
      wallet: nil,
      notice: nil,
      operation: nil
    }

    [
      {AshPlatformWeb.AutolaunchBidComponent,
       Map.merge(common, %{
         id: "preview-bid",
         balance: nil,
         amount: "",
         max_price: "",
         estimate: nil
       })},
      {AshPlatformWeb.AutolaunchLaunchWalletComponent,
       Map.merge(common, %{
         id: "preview-launch",
         draft: %{treasury: "0x1111111111111111111111111111111111111111"},
         treasury_report: nil,
         fresh_treasury_report_id: nil,
         elsewhere?: false
       })},
      {AshPlatformWeb.AutolaunchSubjectWalletComponent,
       Map.merge(common, %{
         id: "preview-subject",
         state: nil,
         kind: :stake,
         asset: "usdc",
         amount: "",
         note: "",
         assets: [],
         action_list: []
       })}
    ]
    |> Enum.map(fn {module, assigns} ->
      html = module.render(assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      %{
        name: inspect(module),
        document:
          "<!doctype html><html data-brand=platform data-theme=dark><head><meta name=viewport content='width=device-width,initial-scale=1'><link rel=stylesheet href=/assets/js/app.css></head><body style='padding:20px'><div inert>#{html}</div></body></html>"
      }
    end)
  end
end
