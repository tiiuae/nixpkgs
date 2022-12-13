# AWK script to generate random path-like strings
BEGIN {
  # Seed with 0 for reproducibility
  srand(seed)

  # Don't include 127 == DEL
  upperascii = 127

  # Creates array chr containing a mapping from integer to the ascii character representing it
  for (i = 0; i < upperascii; i++) {
    chr[i] = sprintf("%c", i)
  }

  # 32 extra weight for .
  upperdot = upperascii + extradotweight
  # 32 extra weight for /
  upperslash = upperdot + extraslashweight
  # 32 extra weight for null, indicating the end of the string
  # Must be at least 1 to trigger the end at all
  total = upperslash + 1 + extranullweight

  new=1
  while (1) {
    value = int(rand() * total)
    if (value < 32) {
      # Don't output non-printable characters, the bash code can't handle newlines well
      continue
    } else if (value < upperascii) {
      printf chr[value]
      new=0
    } else if (value < upperdot) {
      printf "."
      new=0
    } else if (value < upperslash) {
      # If it's the start of a new path, only generate a / in 10% of cases
      if (new && rand() > 0.1) continue
      printf "/"
    } else {
      # If it's the start of a new path, only generate a null in 10% of cases
      if (new && rand() > 0.1) continue
      printf "\x00"
      new=1
    }
  }
}
