# AWK script to generate random path-like strings, separated by null characters
# Customizable variables are (all default to 0):
# - seed: Specifies the deterministic random seed to use for generation
# - count: The number of paths to generate
# - extradotweight: Gives extra weight to dots being generated
# - extraslashweight: Gives extra weight to slashes being generated
# - extranullweight: Gives extra weight to null being generated,
#   therefore making paths shorter
#
# Can be called with
#
#     awk -f ./pathGenerate.awk -v <variable>=<value> \
#       | tr '\0' '\n'
#
BEGIN {
  # Seed for reproducibility
  srand(seed)

  # Don't include special characters below 32
  minascii = 32
  # Don't include DEL at 128
  maxascii = 127
  upperascii = maxascii - minascii

  # add extra weight for ., in addition to the one weight from the ascii range
  upperdot = upperascii + extradotweight

  # add extra weight for /, in addition to the one weight from the ascii range
  upperslash = upperdot + extraslashweight

  # add extra weight for null, indicating the end of the string
  # Must be at least 1 to have strings end at all
  total = upperslash + 1 + extranullweight

  # new=1 indicates that it's a new string
  new=1
  while (count > 0) {

    # Random integer between [0, total)
    value = int(rand() * total)

    if (value < upperascii) {
      # Ascii range
      printf("%c", value + minascii)
      new=0

    } else if (value < upperdot) {
      # Dot range
      printf "."
      new=0

    } else if (value < upperslash) {
      # If it's the start of a new path, only generate a / in 10% of cases
      # This is always an invalid subpath, which is not a very interesting case
      if (new && rand() > 0.1) continue
      printf "/"

    } else {
      # Do not generate empty strings
      if (new) continue
      printf "\x00"
      count--
      new=1
    }
  }
}
