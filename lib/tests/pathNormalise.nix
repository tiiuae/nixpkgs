# Used by ./path.sh
# dir is a flat directory containing files with randomly-generated path-like values
# This file should return a { <value> = <lib.path.subpath.normalise value>; }
# attribute set. If `normalise` fails to evaluate, "" is returned instead.
# If "" is a value, it's not included in the result
{ libpath, dir }:
let
  lib = import libpath;
  inherit (lib.path.subpath) normalise;

  list = builtins.concatMap (name:
    let
      str = builtins.readFile (dir + "/${name}");
      onceRes = builtins.tryEval (normalise str);
      twiceRes = builtins.tryEval (normalise onceRes.value);

      once = {
        name = str;
        value = if onceRes.success then onceRes.value else "";
      };
      twice = {
        name = onceRes.value;
        value = if twiceRes.success then twiceRes.value else "";
      };
    in [ once ] ++ lib.optional onceRes.success twice
  ) (builtins.attrNames (builtins.readDir dir));

  attrs = builtins.listToAttrs list;

  # Remove "" because bash can't handle that
  result = removeAttrs attrs [""];
in result
