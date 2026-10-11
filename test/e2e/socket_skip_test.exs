defmodule Sobelow.SocketSkipTest do
  @moduledoc false
  use Sobelow.ScanCase

  @endpoint_path "lib/basic_web/endpoint.ex"

  defp endpoint(comment) do
    """
    defmodule BasicWeb.Endpoint do
      use Phoenix.Endpoint, otp_app: :basic

      #{comment}
      # The application's callback validates an explicit origin allowlist.
      socket "/annotated", Phoenix.LiveView.Socket,
        websocket: [check_origin: {OriginPolicy, :allowed?, []}]

      socket "/unannotated", Phoenix.LiveView.Socket,
        websocket: [check_origin: false]

      def download(conn, %{"path" => path}) do
        send_file(conn, 200, path)
      end
    end
    """
  end

  test "a socket skip suppresses only its own finding and preserves sibling fingerprints" do
    temp_fixture_file("basic", @endpoint_path, endpoint(~s(# sobelow_skip ["Config.CSWH"])))

    all = findings_for(scan("basic", skip: false), "Config.CSWH")
    assert length(all) == 2
    expected = Enum.find(all, &(&1["confidence"] == "high"))

    assert findings_for(scan("basic", skip: true), "Config.CSWH") == [expected]
  end

  test "parent Config is supported but unrelated checks do not suppress sockets" do
    for {comment, count} <- [{"Config", 1}, {"Config.CSRF", 2}] do
      temp_fixture_file("basic", @endpoint_path, endpoint(~s(# sobelow_skip ["#{comment}"])))

      assert length(findings_for(scan("basic", skip: true), "Config.CSWH")) == count
    end
  end

  test "a socket skip is consumed without leaking onto the next function" do
    temp_fixture_file(
      "basic",
      @endpoint_path,
      endpoint(~s(# sobelow_skip ["Config.CSWH", "Traversal.SendFile"]))
    )

    report = scan("basic", skip: true)
    assert length(findings_for(report, "Config.CSWH")) == 1

    assert Enum.any?(findings_for(report, "Traversal.SendFile"), fn finding ->
             String.ends_with?(finding["file"], "endpoint.ex")
           end)
  end

  test "an intervening declaration prevents a skip from binding to a socket" do
    comment = """
    # sobelow_skip ["Config.CSWH"]
    @unrelated true
    """

    temp_fixture_file("basic", @endpoint_path, endpoint(comment))
    assert length(findings_for(scan("basic", skip: true), "Config.CSWH")) == 2
  end

  test "a skip outside a nested endpoint does not suppress sockets inside it" do
    source = """
    defmodule Outer do
      # sobelow_skip ["Config.CSWH"]
      #{endpoint("")}
    end
    """

    temp_fixture_file("basic", @endpoint_path, source)
    assert length(findings_for(scan("basic", skip: true), "Config.CSWH")) == 2
  end
end
