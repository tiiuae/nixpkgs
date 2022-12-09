# Functions for working with paths, see ./path-design.md
{ lib }:
let

  inherit (builtins)
    isString
    split
    ;

  inherit (lib.lists)
    length
    head
    last
    genList
    elemAt
    ;

  inherit (lib.strings)
    concatStringsSep
    substring
    ;

  inherit (lib.generators)
    toPretty
    ;

  pretty = toPretty { multiline = false; };

  # Returns true if the value is a valid subpath string, otherwise throws an error
  validSubpathString = value: errorPrefix:
    if ! isString value then
      throw "${errorPrefix}: Not a string"
    else if value == "" then
      throw "${errorPrefix}: The string is empty"
    else if substring 0 1 value == "/" then
      throw "${errorPrefix}: The string is an absolute path because it starts with `/`"
    else true;

  # Splits and normalises a subpath string into its components.
  # Errors for ".." components and doesn't include "." components
  splitSubpath = path: errorPrefix:
    let
      # Split the string into its parts using regex for efficiency. This regex
      # matches patterns like "/", "/./", "/././", with arbitrarily many "/"s
      # together. These are the main special cases:
      # - Leading "./" gets split into a leading "." part
      # - Trailing "/." or "/" get split into a trailing "." or ""
      #   part respectively
      #
      # These are the only cases where "." and "" parts can occur
      parts = split "/+(\\./+)*" path;

      # `split` creates a list of 2 * k + 1 elements, containing the k +
      # 1 parts, interleaved with k matches where k is the number of
      # (non-overlapping) matches. This calculation here gets the number of parts
      # back from the list length
      # floor( (2 * k + 1) / 2 ) + 1 == floor( k + 1/2 ) + 1 == k + 1
      partCount = length parts / 2 + 1;

      # To assemble the final list of components we want to:
      # - Skip a potential leading ".", normalising "./foo" to "foo"
      # - Skip a potential trailing "." or "", normalising "foo/" and "foo/." to
      #   "foo"
      skipStart = if head parts == "." then 1 else 0;
      skipEnd = if last parts == "." || last parts == "" then 1 else 0;

      # We can now know the length of the result by removing the number of
      # skipped parts from the total number
      componentCount = partCount - skipEnd - skipStart;

    in
      # Special case of a single "." path component. Such a case leaves a
      # componentCount of -1 due to the skipStart/skipEnd not verifying that
      # they don't refer to the same character
      if path == "." then []

      # And we can use this to generate the result list directly. Doing it this
      # way over a combination of `filter`, `init` and `tail` makes it more
      # efficient, because we don't allocate any intermediate lists
      else genList (index:
        let
          # To get to the element we need to add the number of parts we skip and
          # multiply by two due to the interleaved layout of `parts`
          value = elemAt parts ((skipStart + index) * 2);
        in

        # We don't support ".." components, see ./path-design.md
        if value == ".." then
          throw "${errorPrefix}: Path string contains contains a `..` component, which is not supported"
        # Otherwise just return the part unchanged
        else
          value
      ) componentCount;

  # joins subpath components together
  joinSubpath = components:
    "./" +
    # An empty string is not a valid subpath, so we need to return a `.` when we have no components
    (if components == [] then "."
    else concatStringsSep "/" components);

in /* No rec! Add dependencies on this file just above */ {

  /* Normalises a subpath.

  - Limits repeating `/` to a single one

  - Removes redundant `.` components

  - Errors on empty strings

  - Removes trailing `/` and `/.`

  - Errors on `..` path components

  - Adds leading `./`

  Laws:

  - (Idempotency) Normalising multiple times gives the same result:
    `subpath.normalise (subpath.normalise p) == subpath.normalise p`

  - (Uniqueness) There's only a single normalisation for a path:
    `subpath.normalise p != subpath.normalise q => $(realpath -ms ${p}) != $(realpath -ms ${q})`

  - Doesn't change the path according to `realpath -ms`:
    `$(realpath -ms ${p}) == $(realpath -ms ${subpath.normalise p})`

  Example:
    # limits repeating `/` to a single one
    subpath.normalise "foo//bar"
    => "./foo/bar"

    # removes redundant `.` components
    subpath.normalise "foo/./bar"
    => "./foo/bar"

    # adds leading `./`
    subpath.normalise "foo/bar"
    => "./foo/bar"

    # removes trailing `/`
    subpath.normalise "foo/bar/"
    => "./foo/bar"

    # removes trailing `/.`
    subpath.normalise "foo/bar/."
    => "./foo/bar"

    # Returns the current directory as `./.`
    subpath.normalise "."
    => "./."

    # errors on `..` path components
    subpath.normalise "foo/../bar"
    => <error>

    # errors on empty string
    subpath.normalise ""
    => <error>

    # errors on absolute path
    subpath.normalise "/foo"
    => <error>

  Type:
    subpath.normalise :: String -> String
  */
  subpath.normalise = path:
  assert validSubpathString path "lib.path.subpath.normalise: Argument ${pretty path} is not a valid subpath string";
    let components = splitSubpath path "lib.path.subpath.normalise: Argument ${path} can't be normalised";
    in joinSubpath components;

}
