#!/usr/bin/env bash
set -euo pipefail

# MCP Documentation Setup Script
# This script adds documentation generation to the nix-mcp-servers repository

# Print section header
section() {
  echo
  echo "=== $1 ==="
  echo
}

# Check if we're in the project root
if [ ! -f "flake.nix" ] || [ ! -d "modules" ]; then
  echo "Error: This script must be run from the project root of nix-mcp-servers"
  exit 1
fi

section "Creating documentation directory structure"
mkdir -p modules/documentation

section "Creating documentation module files"

# Create the main documentation module
cat > modules/documentation/default.nix << 'EOF'
# modules/documentation/default.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.documentation;
  
  # Build documentation from module options
  mcpOptionsDoc = pkgs.callPackage ./options-doc.nix {
    inherit (config._module) options;
    inherit (config.services.mcp-clients) version;
    revision = config.services.mcp-clients.revision or "main";
  };
  
in {
  options = {
    documentation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to build MCP documentation.";
      };
    };
  };
  
  config = mkIf cfg.enable {
    system.build = {
      manual = mcpOptionsDoc;
      manualHTML = mcpOptionsDoc.manualHTML;
      optionsJSON = mcpOptionsDoc.optionsJSON;
    };
  };
}
EOF

# Create the options documentation generator
cat > modules/documentation/options-doc.nix << 'EOF'
# modules/documentation/options-doc.nix
{ pkgs, options, version, revision ? "main" }:

with pkgs;

let
  lib = pkgs.lib;
  
  # Transform declarations to GitHub links
  gitHubDeclaration = subpath: {
    url = "https://github.com/aloshy-ai/nix-mcp-servers/blob/${revision}/${subpath}";
    name = "<mcp-servers/${subpath}>";
  };
  
  # Generate options documentation
  optionsDoc = buildPackages.nixosOptionsDoc {
    inherit options;
    transformOptions = opt: opt // {
      # Clean up declaration sites to link to GitHub
      declarations = map (decl:
        if lib.hasPrefix (toString ../.) (toString decl) then
          gitHubDeclaration
            (lib.removePrefix "/" (lib.removePrefix (toString ../.) (toString decl)))
        else decl
      ) opt.declarations;
    };
  };

in rec {
  # JSON options for API consumption
  optionsJSON = runCommand "mcp-options.json" 
    { meta.description = "MCP Servers options in JSON format"; }
    ''
      mkdir -p $out/{share/doc,nix-support}
      cp -a ${optionsDoc.optionsJSON}/share/doc/nixos $out/share/doc/mcp
      substitute \
        ${optionsDoc.optionsJSON}/nix-support/hydra-build-products \
        $out/nix-support/hydra-build-products \
        --replace-fail \
          '${optionsDoc.optionsJSON}/share/doc/nixos' \
          "$out/share/doc/mcp"
    '';

  # HTML manual 
  manualHTML = runCommand "mcp-manual-html"
    { 
      nativeBuildInputs = [ buildPackages.nixos-render-docs ];
      styles = lib.sourceFilesBySuffices (pkgs.path + "/doc") [ ".css" ];
      meta.description = "The MCP Servers Configuration Manual";
      allowedReferences = ["out"];
    }
    ''
      # Generate the HTML manual
      dst=$out/share/doc/mcp
      mkdir -p $dst
      
      # Copy styles and syntax highlighting
      cp $styles/style.css $dst
      cp -r ${pkgs.documentation-highlighter} $dst/highlightjs
      
      # Process markdown template
      substitute ${./manual.md} manual.md \
        --replace-fail '@MCP_VERSION@' "${version}" \
        --replace-fail '@MCP_OPTIONS_JSON@' ${optionsJSON}/share/doc/mcp/options.json
      
      # Check if nixos-render-docs supports redirects
      if nixos-render-docs manual html --help | grep --silent -E '^\s+--redirects\s'; then
        redirects_opt="--redirects ${./redirects.json}"
      fi
      
      # Build HTML
      nixos-render-docs -j $NIX_BUILD_CORES manual html \
        --manpage-urls ${pkgs.writeText "manpage-urls.json" "{}"} \
        --revision ${lib.escapeShellArg revision} \
        --generator "nixos-render-docs ${lib.version}" \
        $redirects_opt \
        --stylesheet style.css \
        --stylesheet highlightjs/mono-blue.css \
        --script ./highlightjs/highlight.pack.js \
        --script ./highlightjs/loader.js \
        --toc-depth 1 \
        --chunk-toc-depth 1 \
        ./manual.md \
        $dst/index.html
      
      mkdir -p $out/nix-support
      echo "nix-build out $out" >> $out/nix-support/hydra-build-products
      echo "doc manual $dst" >> $out/nix-support/hydra-build-products
    '';

  # Index page of the manual
  manualHTMLIndex = "${manualHTML}/share/doc/mcp/index.html";
}
EOF

# Create the manual markdown template
cat > modules/documentation/manual.md << 'EOF'
# MCP Server Configuration Options {#book-mcp-manual}
## Version @MCP_VERSION@

MCP Flake provides declarative configuration for Model Control Protocol servers and clients.

## Introduction

The MCP Flake allows you to easily manage configuration files for AI model interaction using the Model Control Protocol (MCP). This includes support for clients like Claude Desktop, Cursor IDE, VSCode extensions, and others.

## Features

- Cross-platform support (NixOS, Darwin, home-manager)
- Pure Nix expressions for maximum compatibility
- Declarative configuration with support for secret management
- Support for various MCP servers including filesystem and GitHub servers
- Automatic generation of client configurations at appropriate OS-specific paths

## Configuration Options

```{=include=} options
id-prefix: opt-
list-id: mcp-configuration-variable-list
source: @MCP_OPTIONS_JSON@
```
EOF

# Create the redirects configuration
cat > modules/documentation/redirects.json << 'EOF'
{
  "book-mcp-manual": [
    "index.html#book-mcp-manual"
  ]
}
EOF

# Create the documentation evaluation helper
cat > modules/documentation/eval-docs.nix << 'EOF'
# modules/documentation/eval-docs.nix
{ system, pkgs, mcpLib, revision, version }:

let
  localPkgs = pkgs;
  
  # Create minimal module evaluation
  eval = localPkgs.lib.evalModules {
    modules = [
      ./default.nix
      {
        # Module to include for documentation
        imports = [
          ../common/options.nix
          ../common/server-options.nix
          ../common/client-options.nix
        ];
        
        # Set required configuration values
        services.mcp-clients.version = version;
        services.mcp-clients.revision = revision;
        documentation.enable = true;
        
        # Set the system
        _module.args.pkgs = localPkgs;
      }
    ];
    
    # Pass special arguments needed by modules
    specialArgs = {
      modulesPath = builtins.toString ../..;
      lib = localPkgs.lib;
    };
  };

in
  # Return the documentation derivations
  eval.config.system.build.manual
EOF

# Create the module list file
cat > modules/module-list.nix << 'EOF'
# modules/module-list.nix
# List all modules that should be included in documentation
[
  ./common/options.nix
  ./common/server-options.nix
  ./common/client-options.nix
  ./common/implementation.nix
  ./nixos/default.nix
  ./darwin/default.nix
  ./home-manager/default.nix
  ./documentation
]
EOF

section "Updating flake.nix"

# Update flake.nix to include documentation outputs
# This uses sed to add the documentation-related code to the perSystem section
# First, we'll back up the original flake.nix
cp flake.nix flake.nix.bak

# Add documentation generation to flake.nix
# We'll insert the documentation code after the mcp-setup definition
sed -i.temp '
/mcp-setup = pkgs.writeShellScriptBin/,/};/ {
  /};/ {
    r /dev/stdin
    }
}
' flake.nix << 'EOD'
        
        # Build the manual
        documentation = import ./modules/documentation/eval-docs.nix {
          inherit system pkgs;
          mcpLib = import ./lib { inherit (nixpkgs) lib; };
          revision = self.rev or "main";
          version = "0.1.0"; # Change to match your versioning
        };
EOD

# Then add the documentation packages to the packages output
sed -i.temp '
/packages.default = mcp-setup;/ {
  a \
        # Documentation packages\
        packages.manualHTML = documentation.manualHTML;\
        packages.optionsJSON = documentation.optionsJSON;\
        packages.documentation = documentation;\
        \
        # Add documentation to checks\
        checks.manualHTML = documentation.manualHTML;
}
' flake.nix

section "Updating CI configuration"

# Update the CI workflow to enable documentation generation
if [ -f ".github/workflows/ci.yml" ]; then
  # Backup the original CI configuration
  cp .github/workflows/ci.yml .github/workflows/ci.yml.bak
  
  # Update the CI configuration to enable documentation generation
  sed -i.temp 's/build-docs: false/build-docs: true/' .github/workflows/ci.yml
  
  # Add the docs-package parameter
  # Find the line with "visibility: public" and add the docs-package parameter after it
  sed -i.temp '/visibility: public/ a\        docs-package: "manualHTML"' .github/workflows/ci.yml
  
  # Remove temporary files
  rm .github/workflows/ci.yml.temp
else
  echo "Warning: CI configuration file not found at .github/workflows/ci.yml"
  echo "You will need to manually update the CI configuration to enable documentation generation."
fi

# Clean up temporary files
rm flake.nix.temp

section "Setup complete"
echo "Documentation generation has been set up successfully."
echo "To test the documentation generation, run:"
echo
echo "  nix build .#manualHTML"
echo
echo "After pushing these changes to the main branch, the documentation"
echo "will be automatically generated and deployed to GitHub Pages."
