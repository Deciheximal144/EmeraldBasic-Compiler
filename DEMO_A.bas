'#GRAPHICS
' DEMO A - This initial demo creates a top-down adventure using the ASCII font
' where the player can move around the screen. We use CHR$(5) to represent shrubs
' that the player can walk over, since there are no barrier checks yet.

' We'll put constants at the top. Constants are variables that can't be changed.
' They are also program-wide, so we don't need to make them SHARED between functions

CONST heroClr = 3 ' What color the hero character will be drawn in

DIM SHARED map(120, 120) ' An array to store the objects on the map

COMMON SHARED hPosX, hPosY ' Common shared variables are global

hPosX = 10 ' Assign initial values to our global variables, QBASIC won't let us do it on the same line
hPosY = 10

' Place shrubs on our map randomly
map(5, 10) = 1
map(1, 18) = 1
map(5, 10) = 1
map(5, 30) = 1
map(4, 15) = 1
map(5, 19) = 1
map(15, 40) = 1
map(8, 19) = 1

'''' Visual setup ''''
_FULLSCREEN ' QB64 specific commmand to make the window fullscreen. QB64 specific commands start with an underscore
SCREEN 13 ' Screen 13 is 320 x 220. This was a very common mode in the original QBASIC
''''

'''''''''''''''''''''''''''''''''''
DO '''' BEGIN MAIN LOOP, OUTER ''''

  ' DISPLAY CODE

  CLS ' We clear the screen and then draw first thing.

  COLOR 2 ' Green

  ' Draw shrubs
  FOR IY = 1 TO 20
    FOR IX = 1 TO 20
      IF map(IY, IX) > 0 THEN ' 1 is the current tile number value of our shrub tile

        LOCATE IY, IX
        PRINT CHR$(5) ' ASCII character 5
      END IF
    NEXT IX
  NEXT IY

  ' Draw hero
  LOCATE hPosY, hPosX
  COLOR heroClr
  PRINT CHR$(2) ' This is the hero ASCII character

  DO '''' INNER LOOP ''''

    IN$ = INKEY$ ' Gather input from keyboard over and over

  LOOP UNTIL IN$ <> ""

  IN$ = UCASE$(IN$)

  ' CONTROL CODE

  ' MOVE UP
  IF IN$ = "8" OR IN$ = CHR$(0) + "H" THEN
    IF hPosY > 1 THEN hPosY = hPosY - 1
  END IF

  ' MOVE LEFT
  IF IN$ = "4" OR IN$ = CHR$(0) + "K" THEN
    IF hPosX > 1 THEN hPosX = hPosX - 1
  END IF

  ' MOVE RIGHT
  IF IN$ = "6" OR IN$ = CHR$(0) + "M" THEN
    IF hPosX < 40 THEN hPosX = hPosX + 1
  END IF

  ' MOVE DOWN
  IF IN$ = "2" OR IN$ = CHR$(0) + "P" THEN
    IF hPosY < 23 THEN hPosY = hPosY + 1 ' 24 would get it at the bottom, but then the text would scroll. Alternately we could use 24 and add ; after print IN$, which prevents the return character from moving down a line.
  END IF


  ' CLOSING OUTER LOOP, OPPORTUNITY TO EXIT PROGRAM
LOOP UNTIL IN$ = "Q" OR IN$ = "*" OR ASC(IN$) = 27 ' ESC, outer loops ends, exits program

'''' END MAIN FUNCTION, EXIT PROGRAM ''''
