I have designed a test program written in the BASIC dialect supported by your
compiler.

This program tests both elements of the 1047 address emulation:

1.  It uses PEEK(1047) to read the current status of the NumLock key. According
    to your compiler's internal parse_PEEK$ implementation, this will return 32
    if NumLock is active (representing bit 5 being set) and 0 if it is inactive.
2.  It then uses POKE 1047, value to change the state. If NumLock is currently
    active, it will poke 0 to turn it off; if it is inactive, it will poke 32 to
    toggle it on. Your compiler's parse_POKE intercepts this write and simulates
    the physical keyboard event via the Windows API.
3.  It performs a busy-wait loop using FOR-NEXT to allow the operating system a
    moment to register and update the virtual keyboard state before performing a
    final check with PEEK(1047) to print the result.

Here is the code for the test program:

PRINT "--- NumLock Peek/Poke Test ---"
PRINT "Checking NumLock state (address 1047)..."

state = PEEK(1047)
PRINT "Current PEEK value:"; state

IF state = 32 THEN
  PRINT "NumLock is currently ON"
  PRINT "Attempting to turn NumLock OFF..."
  POKE 1047, 0
ELSE
  PRINT "NumLock is currently OFF"
  PRINT "Attempting to turn NumLock ON..."
  POKE 1047, 32
END IF

PRINT "Waiting for OS keyboard state to update..."
FOR ii = 1 TO 500000
NEXT

newState = PEEK(1047)
PRINT "New PEEK value:"; newState

IF newState = 32 THEN
  PRINT "NumLock is now ON"
ELSE
  PRINT "NumLock is now OFF"
END IF

END
