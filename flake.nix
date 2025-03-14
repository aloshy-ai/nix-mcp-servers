{
  description = "MCP server configuration management for various clients";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    home-manager,
    darwin,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      perSystem = {
        system,
        pkgs,
        ...
      }: {
        # CLI tool package
        packages.mcp-setup = pkgs.writeShellScriptBin "mcp-setup" ''
          echo "MCP Setup CLI"
          echo "This tool configures MCP clients based on your NixOS/Darwin configuration."
        '';

        # Documentation generation following home-manager pattern
        packages = rec {
          mcp-setup = pkgs.writeShellScriptBin "mcp-setup" ''
            echo "MCP Setup CLI"
            echo "This tool configures MCP clients based on your NixOS/Darwin configuration."
          '';

          # Load all modules to get documentation
          eval = pkgs.lib.evalModules {
            modules = [
              {imports = [./modules/common];}
            ];
            specialArgs = {inherit pkgs;};
          };

          # Options documentation in different formats
          optionsMD = pkgs.nixosOptionsDoc {
            options = eval.options;
            transformOptions = opt:
              opt
              // {
                declarations = map (d: d.outPath) (opt.declarations or []);
              };
          };

          optionsJSON =
            (pkgs.nixosOptionsDoc {
              options = eval.options;
              transformOptions = opt:
                opt
                // {
                  declarations = map (d: d.outPath) (opt.declarations or []);
                };
              json = true;
            })
            .optionsJSON;

          # Generate HTML manual
          docs =
            pkgs.runCommand "mcp-servers-manual" {
              nativeBuildInputs = [pkgs.buildPackages.pandoc];
            } ''
              # Create output directories
              mkdir -p $out/share/doc/mcp-servers

              # Copy the options documentation
              cp ${optionsMD.optionsCommonMark} $out/share/doc/mcp-servers/options.md
              cp ${optionsJSON} $out/share/doc/mcp-servers/options.json

              # Copy static documentation files
              cp -r ${./docs}/* $out/share/doc/mcp-servers/

              # Copy module files for reference
              mkdir -p $out/share/doc/mcp-servers/modules
              cp -r ${./modules/common}/*.nix $out/share/doc/mcp-servers/modules/

              # Create an index HTML file that can browse the documentation
              cat > $out/share/doc/mcp-servers/index.html << EOF
              <!DOCTYPE html>
              <html>
              <head>
                <meta charset="utf-8">
                <title>MCP Servers Documentation</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  body {
                    font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
                    max-width: 1200px;
                    margin: 0 auto;
                    padding: 20px;
                    line-height: 1.6;
                    color: #333;
                  }
                  h1, h2, h3 { color: #2462c2; }
                  h1 { border-bottom: 1px solid #eee; padding-bottom: 0.3em; }
                  code { background: #f6f8fa; padding: 2px 4px; border-radius: 3px; font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace; }
                  pre { background: #f6f8fa; padding: 16px; border-radius: 6px; overflow-x: auto; }
                  a { color: #0366d6; text-decoration: none; }
                  a:hover { text-decoration: underline; }
                  .option-path { font-weight: bold; background-color: #f0f7ff; border-left: 3px solid #2462c2; padding: 8px 12px; margin: 20px 0 10px 0; }
                  .option-type { color: #6a737d; font-style: italic; }
                  .option-default { background-color: #f6f8fa; padding: 8px; border-radius: 3px; margin-top: 5px; }
                  .option-description { margin-top: 10px; }
                  details { margin: 10px 0; }
                  summary { cursor: pointer; }
                  nav { background: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
                  nav ul { list-style-type: none; padding: 0; margin: 0; }
                  nav li { margin-bottom: 8px; }
                </style>
              </head>
              <body>
                <h1>MCP Servers Documentation</h1>

                <nav>
                  <h2>Contents</h2>
                  <ul>
                    <li><a href="README.md">Introduction</a></li>
                    <li><a href="options.md">Configuration Options</a></li>
                    <li><a href="RELEASE_NOTES.md">Release Notes</a></li>
                  </ul>
                </nav>

                <div id="intro">
                  <h2>Introduction</h2>
                  <p>This documentation provides information about all configuration options for the MCP servers and clients.</p>
                  <p>These modules allow you to configure various model serving setups across different platforms.</p>
                  <p><a href="README.md">Read the full introduction</a></p>
                </div>

                <div id="main-content">
                  <p>Select a section from the navigation menu to view documentation.</p>

                  <h2>Configuration Options</h2>
                  <p>The <a href="options.md">options documentation</a> provides a complete reference of all available configuration options.</p>

                  <h2>Getting Started</h2>
                  <p>See the <a href="README.md">introduction</a> for installation and basic configuration instructions.</p>
                </div>
              </body>
              </html>
              EOF

              # Create a manpage for the main configuration options
              mkdir -p $out/share/man/man5
              pandoc --standalone --to man ${optionsMD.optionsCommonMark} \
                -o $out/share/man/man5/mcp-servers-configuration.5
            '';

          # Main documentation output
          default = docs;
        };
      };

      flake = {
        lib = import ./lib {
          inherit (nixpkgs) lib;
        };

        nixosModules = {
          default = {...}: {
            imports = [
              ./modules/common
              ./modules/nixos
            ];
          };

          home-manager = {...}: {
            imports = [
              ./modules/common
              ./modules/home-manager
            ];
          };
        };

        darwinModules = {
          default = {...}: {
            imports = [
              ./modules/common
              ./modules/darwin
            ];
          };

          home-manager = {...}: {
            imports = [
              ./modules/common
              ./modules/home-manager
            ];
          };
        };
      };
    };
}
