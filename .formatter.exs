[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{ex,exs}",
    "{config,lib,test}/**/*.{ex,exs}",
    "lib/ex_blog_web/{components,controllers,live}/**/*.heex"
  ]
]
