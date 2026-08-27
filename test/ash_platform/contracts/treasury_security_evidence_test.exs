defmodule AshPlatform.Contracts.TreasurySecurityEvidenceTest do
  use ExUnit.Case, async: true

  @manifest Path.expand("../../../contracts/treasury-security-evidence.yaml", __DIR__)
  @abi Path.expand("../../../contracts/abi/safe-v1.json", __DIR__)

  test "THE_PINNED_SAFE_MANIFEST_NAMES_EXACT_BASE_EVIDENCE_AND_ABI_BYTES" do
    manifest = YamlElixir.read_from_file!(@manifest)
    abi_sha = :crypto.hash(:sha256, File.read!(@abi)) |> Base.encode16(case: :lower)

    assert manifest["chain_id"] == 8453
    assert get_in(manifest, ["source", "package"]) == "@safe-global/safe-deployments"
    assert get_in(manifest, ["source", "version"]) == "1.37.54"
    assert get_in(manifest, ["source", "asset_version"]) == "1.4.1"
    assert get_in(manifest, ["safe", "singleton", "version"]) == "1.4.1"

    assert get_in(manifest, ["safe", "singleton", "address"]) ==
             "0x41675c099f32341bf84bfc5382af534df5c7461a"

    assert get_in(manifest, ["safe", "proxy_factory", "address"]) ==
             "0x4e1dcf7ad4e460cfd30791ccc4f9c8a4f820ec67"

    assert get_in(manifest, ["safe", "proxy_runtime", "factory_created_proxy"]) ==
             "0x28fdac6c7b06bb095b9f4fa5a65a552bb8e38f51"

    assert get_in(manifest, ["safe", "proxy_runtime", "creation_transaction"]) ==
             "0xb3b50601312a9a06f7241ba25d05e7b52c785462b3e5d7ac60aaa22a7b7195d9"

    assert get_in(manifest, ["safe", "proxy_runtime", "creation_block_number"]) == 50_538_413

    assert get_in(manifest, ["safe", "admitted_fallback_handlers"]) == [
             "0x0000000000000000000000000000000000000000",
             "0xfd0732dc9e303f09fcef3a7388ad10a83459ec99"
           ]

    assert get_in(manifest, ["tokens", "usdc"]) ==
             "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

    assert get_in(manifest, ["tokens", "regent"]) ==
             "0x6f89bca4ea5931edfcb09786267b251dee752b07"

    assert get_in(manifest, ["safe", "abi", "sha256"]) == abi_sha
    assert manifest["splits"]["admitted_contracts"] == []
  end
end
