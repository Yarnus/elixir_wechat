defmodule WeChat do
  @moduledoc false
  require Logger

  alias WeChat.Builder
  alias WeChat.APIGenerator

  @external_resource Path.join(Path.dirname(__DIR__), "config/wechat_api.toml")

  defmodule UploadMedia do
    @moduledoc """
    ## Example

      ```elixir
      defmodule MyClient do
        use WeChat, appid: "myappid"
      end

      media = %WeChat.UploadMedia{
        file_path: "path_to_file",
        type: "image"
      }
      MyClient.media(:post_form, :upload, %{media: media})
      ```
    """
    @type t :: %__MODULE__{
            file_path: String.t(),
            type:
              {:image, String.t()}
              | {:voice, String.t()}
              | {:video, String.t()}
              | {:thumb, String.t()}
          }
    @enforce_keys [:file_path, :type]
    defstruct [:file_path, :type]
  end

  defmodule UploadMediaContent do
    @moduledoc """
    ## Example

      ```elixir
      defmodule MyClient do
        use WeChat, appid: "myappid"
      end

      file_content = File.read!("path_to_file")
      media = %WeChat.UploadMediaContent{
       file_content: file_content,
       file_name: "myfilename",
       type: "image"
      }
      MyClient.media(:post_form, :upload, %{media: media})
      ```
    """
    @type t :: %__MODULE__{
            file_content: binary(),
            file_name: String.t(),
            type:
              {:image, String.t()}
              | {:voice, String.t()}
              | {:video, String.t()}
              | {:thumb, String.t()}
          }
    @enforce_keys [:file_content, :file_name, :type]
    defstruct [:file_content, :file_name, :type]
  end

  defmodule Error do
    @derive {Jason.Encoder, only: [:errcode, :message, :reason]}
    defexception errcode: nil, message: nil, reason: nil

    def message(%__MODULE__{errcode: errcode, message: message, reason: reason}) do
      "errcode: #{inspect(errcode)}, message: #{inspect(message)}, reason: #{inspect(reason)}"
    end
  end

  defmodule Token do
    @type t :: %__MODULE__{
            access_token: String.t(),
            refresh_token: String.t()
          }
    defstruct [:access_token, :refresh_token]
  end

  def ensure_implements(module, behaviour, message) do
    all = Keyword.take(module.__info__(:attributes), [:behaviour])
    unless [behaviour] in Keyword.values(all) do
      raise %Error{reason: :invalid_impl, message: "Expected #{inspect module} to implement #{inspect behaviour} " <> "in order to #{message}"}
    end
  end

  defmacro __using__(opts \\ []) do
    opts =
      opts
      |> Macro.prewalk(&Macro.expand(&1, __CALLER__))
      |> supplement_options()

    quote do
      require Logger

      Logger.info("initialize module: #{__MODULE__} with options: #{inspect(unquote(opts))}")

      @wechat_app_module __MODULE__
      @wechat_appid Keyword.get(unquote(opts), :appid)
      @scenario Keyword.get(unquote(opts), :scenario)
      @adapter_storage Keyword.get(unquote(opts), :adapter_storage)

      if Keyword.get(unquote(opts), :using_wechat_common_behaviour, true) do
        unquote(generate_base(opts))
      end
      unquote(generate_apis(opts))
    end
  end

  defp supplement_options(opts) do
    using_wechat_common_behaviour = Keyword.get(opts, :using_wechat_common_behaviour, true)

    if using_wechat_common_behaviour == true do
      scenario = Keyword.get(opts, :scenario, :client)

      adapter_storage =
        if scenario == :client do
          Keyword.get(opts, :adapter_storage, WeChat.Storage.Default)
        else
          Keyword.get(opts, :adapter_storage)
        end

      verify_adapter_storage(scenario, adapter_storage)

      Keyword.merge(opts, [
        adapter_storage: adapter_storage,
        scenario: scenario,
      ])
    else
      opts
    end
  end

  defp generate_base(opts) do
    quote do
      if @wechat_appid != nil do
        unquote(generate_base_norequire_appid(opts))
      else
        unquote(generate_base_require_appid(opts))
      end
    end
  end

  defp generate_base_norequire_appid(opts) do
    quote do
      if @scenario == :hub do

        def get_access_token() do
          unquote(__MODULE__).Base.get_access_token(@wechat_appid, __MODULE__, @scenario, unquote(opts))
        end

        def set_access_token(response_body, options) do
          unquote(__MODULE__).Base.set_access_token(response_body, options, unquote(opts))
        end

        def clean_access_token(options) do
          unquote(__MODULE__).Base.clean_access_token(@wechat_appid, options, unquote(opts))
        end

      else

        def get_access_token() do
          unquote(__MODULE__).Base.get_access_token(@wechat_appid, __MODULE__, @scenario, unquote(opts))
        end

        def clean_access_token(options) do
          unquote(__MODULE__).Base.clean_access_token(@wechat_appid, options, unquote(opts))
        end

      end
    end
  end

  defp generate_base_require_appid(opts) do
    quote do
      if @scenario == :hub do

        def get_access_token(appid) do
          unquote(__MODULE__).Base.get_access_token(appid, __MODULE__, @scenario, unquote(opts))
        end

        def set_access_token(response_body, options) do
          unquote(__MODULE__).Base.set_access_token(response_body, options, unquote(opts))
        end

        def clean_access_token(appid, options) do
          unquote(__MODULE__).Base.clean_access_token(appid, options, unquote(opts))
        end

      else

        def get_access_token(appid) do
          unquote(__MODULE__).Base.get_access_token(appid, __MODULE__, @scenario, unquote(opts))
        end

        def clean_access_token(appid, options) do
          unquote(__MODULE__).Base.clean_access_token(appid, options, unquote(opts))
        end

      end
    end
  end

  defp generate_apis(opts) do
    APIGenerator.execute(opts, List.first(@external_resource), Builder)
  end

  defp verify_adapter_storage(_scenario = :client, nil) do
    raise %Error{reason: :adapter_storage_is_nil, message: "Required adapter_storage is nil  when using as client"}
  end
  defp verify_adapter_storage(_scenario = :client, adapter_storage) do
    ensure_implements(adapter_storage, WeChat.Adapter.Storage.Client, "config adapter_storage as client")
  end
  defp verify_adapter_storage(_scenario = :hub, nil) do
    raise %Error{reason: :adapter_storage_is_nil, message: "Required adapter_storage is nil when using as hub"}
  end
  defp verify_adapter_storage(_scenario = :hub, adapter_storage) do
    ensure_implements(adapter_storage, WeChat.Adapter.Storage.Hub, "config adapter_storage as hub")
  end

end

defmodule WeChat.Base do
  @moduledoc false
  require Logger

  alias WeChat.Http

  def get_access_token(appid, module, scenario = :hub, opts) do
    adapter_storage = Keyword.get(opts, :adapter_storage)
    token = adapter_storage.get_access_token(appid)
    Logger.info("scenario as #{scenario}, get_access_token: #{inspect token}")

    if token != nil and token.access_token != nil do
      token.access_token
    else
      access_token = remote_get_access_token(appid, module)
      Logger.info("scenario as #{scenario}, get access_token from remote: #{inspect access_token}")
      access_token
    end
  end
  def get_access_token(appid, _module, scenario = :client, opts) do
    adapter_storage = Keyword.get(opts, :adapter_storage)
    token = adapter_storage.get_access_token(appid)
    Logger.info("scenario as #{scenario}, get_access_token: #{inspect token}")
    token.access_token
  end

  def set_access_token(response_body, options, opts) do
    adapter_storage = Keyword.get(opts, :adapter_storage)

    Logger.info("set_access_token, response_body: #{inspect response_body}, options: #{inspect options}")
    access_token = Map.get(response_body, "access_token")
    appid = Http.grep_appid(options)
    adapter_storage.save_access_token(appid, access_token)
  end

  def clean_access_token(appid, options, opts) do
    adapter_storage = Keyword.get(opts, :adapter_storage)
    access_token = Keyword.get(options, :access_token)
    Logger.info("clean access_token for appid: #{appid}, expired access_token: #{access_token}")
    adapter_storage.delete_access_token(appid, access_token)
  end

  defp remote_get_access_token(appid, module) do
    request_result =
      cond do
        function_exported?(module, :token, 4) ->
          apply(module, :token, [:get, appid])
        true ->
          apply(module, :token, [:get])
      end
    case request_result do
      {:ok, response} ->
        Map.get(response.body, "access_token")
      {:error, error} ->
        Logger.error("remote_get_access_token error: #{inspect error}")
        raise error
    end
  end

end
