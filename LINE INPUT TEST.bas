'''' LINE INPUT TEST
'#GRAPHICS 640, 480
SCREEN _NEWIMAGE(640, 480, 13), 1, 0

COLOR 14
PRINT "--- LINE INPUT Interactive Echo Test ---"
COLOR 15
PRINT ""

LINE INPUT "Enter a word ", favColor$
PRINT "The word you entered is: " + favColor$
PRINT ""

LINE INPUT "Enter a number: ", numStr$
numVal = VAL(numStr$)
PRINT "Double that number is: "; numVal * 2
PRINT ""

PRINT "To verify a read, type the word EXIT (upper or lowercase):";
LINE INPUT cmd$

PRINT ""
PRINT "You typed: " + cmd$

IF UCASE$(cmd$) = "EXIT" THEN
  PRINT "Status: Matches EXIT correctly!"
ELSE
  PRINT "Status: Does NOT match EXIT"
END IF

PRINT
PRINT "Press any key to close."
DO
LOOP UNTIL INKEY$ <> ""

