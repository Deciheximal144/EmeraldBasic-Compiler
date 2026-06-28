'#GRAPHICS 352, 256
' Demo B: In this demo, we'll turn the shrubs into trees, and add barrier checks
' to make it impossible to walk past them. These will happen in the function moveCheck.
' We also create a function to ESCAPE to exit with a code (as yet unused) for future debugging.
' The function createMap now handles tree placement.

'''' Visual setup ''''
_FULLSCREEN
SCREEN _NEWIMAGE(352, 256, 13) ' We've changed to a custom resolution. ' The 13 mimics the SCREEN 13 mode which allows 256 colors
_FONT 8 ' QB64 specific command to ensure the font is 8 x 8 in this mode
''''


CONST heroClr = 3 ' What color the hero character will be drawn in.

CONST mObjTree = 16 ' Map objects hold the value of the item at an X and Y on the screen.
''''''''''''''''''''' The value of 16 was chosen to give room for tiles you can walk over.

DIM SHARED map(120, 120) ' An array to store the objects on the map like trees

COMMON SHARED viewSizeTilesX, viewSizeTilesY, viewStartX, viewStartY, mapSizeX, mapSizeY
COMMON SHARED hPosx, hPosy, barrierNum



viewSizeTilesX = 31 ' Farthest location right on the playscreen
viewSizeTilesY = 23 ' Farthest location down On the playscreen
viewStartX = 2 ' Remember it is not pixels, but ASCII spacing
viewStartY = 1 ' Make a multiple of 8 pixels

mapSizeX = 31 ' Since it doesn't scroll, I like to make this an
mapSizeY = 23 ' odd number, gives a nice symmetry for an exit gap placed in the center

hPosx = 5
hPosy = 5

barrierNum = 16 ' If tile numbers are higher than this, the player can't move through them
'''''''''''''''' We can change this later

' Our little green tree placement commands have been moved into a function named createMap
createMap ' CALL command is optional with no arguments(ex.), and mandatory with them

'''''''''''''''''''''''''''''''''''

DO '''' BEGIN MAIN LOOP, OUTER ''''

  CLS ' We clear the screen and then draw first thing.

  LINE (0, 0)-(7, 7), 4, B ' A demo square to show where the screen starts, use B for box, BF for box fill
  LINE (15, 7)-(264, 192), 14, B ' A box around our active play screen

  ' DRAW TREES

  COLOR 2 ' Green
  FOR iy = 0 TO (viewSizeTilesY - 1)
    FOR ix = 0 TO (viewSizeTilesX - 1)
      IF map(ix, iy) = mObjTree THEN ' notice this says mObjTree now. We'll have different tiles.

        LOCATE iy + viewStartY + 1, ix + viewStartX + 1 ' The +1 is because LOCATE starts at 1
        PRINT CHR$(6);
      END IF
    NEXT ix
  NEXT iy

  ' Draw hero, after drawing terrain:
  LOCATE hPosy + viewStartY + 1, hPosx + viewStartX + 1 ' The +1 is because LOCATE starts at 1
  COLOR heroClr
  PRINT CHR$(2); ' Show hero

  ' Display game info ''''''''''''
  COLOR 15 ' white
  LOCATE 3, 35: PRINT "HX:"; LTRIM$(STR$(hPosx)) ' LTRIM because numbers add spaces around them, STR to convert to string because you can't use LTRIM on numbers
  LOCATE 4, 35: PRINT "HY:"; LTRIM$(STR$(hPosy))

  DO '''' INNER LOOP ''''

    IN$ = INKEY$

  LOOP UNTIL IN$ <> ""

  IN$ = UCASE$(IN$)

  ' CONTROL CODE

  ' MOVE UP
  IF IN$ = "8" OR IN$ = CHR$(0) + "H" THEN

    ff = moveCheck(hPosx, hPosy - 1)

    IF hPosy > 0 AND ff = 0 THEN hPosy = hPosy - 1
  END IF

  ' MOVE LEFT
  IF IN$ = "4" OR IN$ = CHR$(0) + "K" THEN

    ff = moveCheck(hPosx - 1, hPosy)

    IF hPosx > 0 AND ff = 0 THEN hPosx = hPosx - 1

  END IF

  ' MOVE RIGHT
  IF IN$ = "6" OR IN$ = CHR$(0) + "M" THEN

    ff = moveCheck(hPosx + 1, hPosy)

    IF hPosx < (mapSizeX - 1) AND ff = 0 THEN hPosx = hPosx + 1
  END IF

  ' MOVE DOWN
  IF IN$ = "2" OR IN$ = CHR$(0) + "P" THEN

    ff = moveCheck(hPosx, hPosy + 1)

    IF hPosy < (mapSizeY - 1) AND ff = 0 THEN hPosy = hPosy + 1
  END IF

  ' CLOSE OUTER LOOP, OPPORTUNITY TO EXIT PROGRAM

LOOP UNTIL IN$ = "Q" OR IN$ = "*" OR ASC(IN$) = 27 ' ESC, outer loops ends, exits program

' We don't need to put SYSTEM to end the program here, as this is the end of the main function, so the program ends

'''' END MAIN FUNCTION, EXIT PROGRAM ''''
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB createMap ()

  FOR ix = 0 TO (viewSizeTilesX - 1) ' Draw line of trees at top and bottom border
    map(ix, 0) = mObjTree
    map(ix, viewSizeTilesY - 1) = mObjTree ' Bottom row
  NEXT

  FOR iy = 0 TO (viewSizeTilesY - 1) ' Draw line of trees at top and bottom border
    map(0, iy) = mObjTree
    map(viewSizeTilesX - 1, iy) = mObjTree ' Right row
  NEXT

  ' TREES THROWN IN RANDOMLY

  map(1, 5) = mObjTree
  map(5, 6) = mObjTree
  map(8, 8) = mObjTree
  map(4, 15) = mObjTree
  map(5, 19) = mObjTree
  map(15, 12) = mObjTree
  map(8, 19) = mObjTree

END SUB

'''''''''''''''''''''''''''''''''''''''''''''''''''''''
FUNCTION moveCheck (wPosX, wPosY)

  IF wPosX < 0 OR wPosY < 0 THEN EXIT FUNCTION ' Don't flag, just exit, could be walking off map

  IF map(wPosX, wPosY) >= barrierNum THEN
    moveCheck = 1
    EXIT FUNCTION
  END IF

  moveCheck = 0 '' return zero otherwise

END FUNCTION

''''''''''''''''''''''''''''''''''''''

SUB ESCAPE (escapeCode) ' I like to put this one as the last function
  COLOR 15
  LOCATE 5, 10
  PRINT "PROGRAM ENDED WITH CODE:"; escapeCode; "    "

  END ' SYSTEM would also work
END SUB


