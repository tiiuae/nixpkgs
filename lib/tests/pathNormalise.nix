# Used by ./path.sh
#
# stringsDir is a flat directory containing files with randomly-generated
# path-like values
#
# This file should return a { <value> = <lib.path.subpath.normalise value>; }
# attribute set for each value. If `normalise` fails to evaluate,
# "" is returned instead. If not, the result is normalised again and returned
# too
{ libpath, stringsDir }:
let
  lib = import libpath;
  inherit (lib.path.subpath) normalise;

  list = builtins.concatMap (name:
    let
      str = builtins.readFile (stringsDir + "/${name}");

      onceRes = builtins.tryEval (normalise str);
      once = [{
        name = str;
        value = if onceRes.success then onceRes.value else "";
      }];

      # Only try normalising it twice if the first normalisation succeeded
      twiceRes = builtins.tryEval (normalise onceRes.value);
      twice = lib.optional onceRes.success {
        name = onceRes.value;
        value = if twiceRes.success then twiceRes.value else "";
      };
    in once ++ twice
  ) (builtins.attrNames (builtins.readDir stringsDir));

in builtins.listToAttrs list
