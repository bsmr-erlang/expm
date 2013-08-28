defmodule Expm.Server do
  use Application.Behaviour
  alias GenX.Supervisor, as: Sup
  alias :cowboy, as: Cowboy

  def start(_, _) do
   Application.start(:bcrypt) # because we don't want to start it in the CLI
   env = Application.environment(:expm)
   repo = env[:repository] || quote do: Expm.Repository.DETS.new(filename: "expm.dat")
   static_dir = Path.join [Path.dirname(:code.which(__MODULE__)), "..", "priv", "static"]
   {repository, _} = Code.eval_quoted repo, [env: env]
   dispatch = [
      {:_, [{"/", Expm.Server.Http.List, [repository: repository]},
            {"/favicon.ico", :cowboy_static, [file: "favicon.ico", directory: static_dir]},
            {"/__download__/expm", :cowboy_static, [file: "expm", directory: static_dir]},
            {"/s/[:...]", :cowboy_static, [directory: static_dir, mimetypes: {&:mimetypes.path_to_mimes/2, :default}]},
            {"/__version__", Expm.Server.Http.Version, []},
            {"/:package", Expm.Server.Http.Package, [repository: repository]},
            {"/:package/:version", Expm.Server.Http.PackageVersion, [repository: repository]},
            ]},
   ] |> :cowboy_router.compile
   http_port = env[:http_port]
   {:ok, _} = Cowboy.start_http Expm.Server.Http.Listener, 100, [port: http_port], [env: [dispatch: dispatch]]
   Lager.info "Started expm server on port #{http_port}"
   Sup.start_link sup_tree
  end

  defp sup_tree do
    Sup.OneForOne.new(id: Expm.Server.Sup)
  end
end

defmodule Expm.Server.Http do

  alias :cowboy_req, as: Req

  defmacro __using__(_) do
    quote do
      alias :cowboy_req, as: Req
      defrecord State, opts: [], endpoint: nil, repository: nil, package: nil

      def init({:tcp, :http}, _req, _opts) do
        {:upgrade, :protocol, :cowboy_rest}
      end

      def rest_init(req, opts) do
        repository = Expm.Repository.Auth.new repository: opts[:repository]
        {:ok, req, __MODULE__.State.new(opts: opts, endpoint: opts[:endpoint], repository: repository)}
      end

      def allowed_methods(req, state) do
        {["GET", "PUT", "POST", "DELETE"], req, state}
      end

      def content_types_provided(req, __MODULE__.State[] = state) do
        {[
           {{<<"text">>, <<"html">>, []}, :to_html},
           {{<<"application">>, <<"elixir">>, []}, :to_elixir},
         ], req, state}
      end

      def content_types_accepted(req, state) do
        {[{{"application","elixir", []}, :process_elixir}], req, state}
      end

      def terminate(_req, _state), do: :ok

      defoverridable allowed_methods: 2, rest_init: 2, terminate: 2
    end
  end


  def render_page(content, req, state, assigns // []) do
    Expm.Server.Templates.page(content, Keyword.merge(page_assigns(req, state), assigns))
  end

  defp page_assigns(req, _state) do
    {host, req} = Req.host(req)
    {port, req} = Req.port(req)
    {path, _req} = Req.path(req)
    motd_file = Path.join [Path.dirname(__FILE__), "..", "priv", "motd"]
    if File.exists?(motd_file) and path == "/" do
      {:ok, motd} = File.read(motd_file)
    else
      motd = ""
    end
    if port == 80 do
      port = ""
    else
      port = ":#{port}"
    end
    title = Application.environment(:expm)[:site_title]
    subtitle = Application.environment(:expm)[:site_subtitle]
    [host: host, port: port, motd: motd, title: title, subtitle: subtitle]
  end
end