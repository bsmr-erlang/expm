defmodule Expm.Server.Http.PackageVersion do
  use Expm.Server.Http

  def allowed_methods(req, state) do
    {["GET"], req, state}
  end

  def resource_exists(req, State[repository: repository] = state) do
    {package, req} = Req.binding(:package, req)  
    {version, req} = Req.binding(:version, req)        
    pkg = Expm.Package.fetch repository, package, version
    {pkg != :not_found, req, state.package(pkg)}
  end

  def to_html(req, State[repository: repository, package: pkg] = state) do
    out = Expm.Server.Http.render_page(Expm.Server.Templates.package(pkg, repository), req, state)
    {out, req, state}
  end

  def to_elixir(req, State[package: pkg] = state) do
    {pkg.encode, req, state}
  end

end
