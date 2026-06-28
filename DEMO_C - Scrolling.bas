' Demo C: Adds scrolling to our game
' Also adds a ZLOCATE function that lets us use X, Y instead of Y, X

CONST SCREENSIZEX = 376
CONST SCREENSIZEY = 256

'''' Visual setup ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
_FULLSCREEN
SCREEN _NEWIMAGE(SCREENSIZEX, SCREENSIZEY, 13) ' The 13 mimics the SCREEN 13 mode which allows 256 colors
_FONT 8 ' QB64 specific command to ensure the font is 8 x 8 in this mode
''''''''''''''''''''''

CONST heroClr = 3

CONST mObjTree = 16 ' Map objects hold the value of the item at an X and Y on the screen

DIM SHARED map(120, 120) ' An array to store the objects on the map like trees

COMMON SHARED viewCenterPosX, viewCenterPosY, viewSizeTilesX, viewSizeTilesY, viewStartX, viewStartY
COMMON SHARED hTruePosX, hTruePosY, hScrPosX, hScrPosY, mapSizeX, mapSizeY, mapPosX, mapPosY
COMMON SHARED barrierNum


viewCenterPosX = 15
viewCenterPosY = 11

' We're going to make the viewSizeTilesX and Y variables twice the viewCenterPos position plus to 1 - works out to 31 x 23

viewSizeTilesX = (viewCenterPosX * 2) + 1 ' Farthest location right on the playscreen
viewSizeTilesY = (viewCenterPosY * 2) + 1 ' Farthest location down on the playscreen

viewStartX = 2 ' Remember it is not pixels, but ASCII spacing
viewStartY = 1 ' This makes the true pixel start position for drawing the map a multiple of 8

mapSizeX = 40 ' A bit larger now since we scroll
mapSizeY = 32

' Since there is scrolling, there needs to be a way to have map offset and hero offset positions
' We'll switch to a new plan for tracking the player's position. hTruePosX and hTruePosY will track the player's
' true position, and we'll have it periodically split into mapPos* and hScrPos using the subroutine splitPos

hTruePosX = 5
hTruePosY = 5

barrierNum = 16 ' If tile numbers are greater or equal to this, the player can't move through them

''''''

createMap

DO '''' BEGIN MAIN LOOP, OUTER ''''

  CLS

  ' New: this line around the screen uses fancy math so that if we change the viewStart or viewSize, the border changes too
  LINE ((viewStartX * 8) - 1, (viewStartY * 8) - 1)-((viewStartX * 8) + (viewSizeTilesX * 8), (viewStartY * 8) + (viewSizeTilesY * 8)), 14, B

  CALL splitPos(hTruePosX, hTruePosY) ' Pass the true X and Y positions to be split into map and screen positions

  COLOR 2 ' Green
  ' DRAW TREES
  FOR iy = 0 TO (viewSizeTilesY - 1)
    FOR ix = 0 TO (viewSizeTilesX - 1)
      IF map(mapPosX + ix, mapPosY + iy) = mObjTree THEN

        ZLOCATE ix + viewStartX, iy + viewStartY
        PRINT CHR$(6);
      END IF
    NEXT ix
  NEXT iy

  ' Draw hero, after drawing terrain:
  ZLOCATE viewStartX + hScrPosX, viewStartY + hScrPosY
  COLOR heroClr
  PRINT CHR$(2); ' Show hero

  textX = 34 ' In case we want to change where the text shows on the X axis easily.

  ' Display game info ''''''''''''
  COLOR 15 ' white
  ZLOCATE textX, 3: PRINT "TX:"; LTRIM$(STR$(hTruePosX))
  ZLOCATE textX, 4: PRINT "TY:"; LTRIM$(STR$(hTruePosY))
  COLOR 11 ' light blue
  ZLOCATE textX, 5: PRINT "MX:"; LTRIM$(STR$(mapPosX))
  COLOR 15 ' white
  ZLOCATE textX + 5, 5
  PRINT " SX:"; LTRIM$(STR$(hScrPosX))
  COLOR 11 ' light blue
  ZLOCATE textX, 6: PRINT "MY:"; LTRIM$(STR$(mapPosY));
  COLOR 15 ' white
  ZLOCATE textX + 5, 6
  PRINT " SY:"; LTRIM$(STR$(hScrPosY))

  DO '''' INNER LOOP ''''

    IN$ = INKEY$

  LOOP UNTIL IN$ <> "" ''''

  IN$ = UCASE$(IN$)

  ' CONTROL CODE

  ' MOVE UP
  IF IN$ = "8" OR IN$ = CHR$(0) + "H" THEN

    ff = moveCheck(hTruePosX, hTruePosY - 1)

    IF hTruePosY > 0 AND ff = 0 THEN hTruePosY = hTruePosY - 1
  END IF

  ' MOVE LEFT
  IF IN$ = "4" OR IN$ = CHR$(0) + "K" THEN

    ff = moveCheck(hTruePosX - 1, hTruePosY)

    IF hTruePosX > 0 AND ff = 0 THEN hTruePosX = hTruePosX - 1

  END IF

  ' MOVE RIGHT
  IF IN$ = "6" OR IN$ = CHR$(0) + "M" THEN

    ff = moveCheck(hTruePosX + 1, hTruePosY)

    IF hTruePosX < (mapSizeX - 1) AND ff = 0 THEN hTruePosX = hTruePosX + 1
  END IF

  ' MOVE DOWN
  IF IN$ = "2" OR IN$ = CHR$(0) + "P" THEN

    ff = moveCheck(hTruePosX, hTruePosY + 1)

    IF hTruePosY < (mapSizeY - 1) AND ff = 0 THEN hTruePosY = hTruePosY + 1
  END IF

  ' CLOSE OUTER LOOP, OPPORTUNITY TO EXIT PROGRAM

LOOP UNTIL IN$ = "Q" OR IN$ = "*" OR ASC(IN$) = 27 ' ESC, outer loops ends, exits program

' We don't need to put SYSTEM to end the program here, as this is the end of the main function, so the program ends

'''' END MAIN FUNCTION, EXIT PROGRAM ''''
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB createMap ()

  clearMap

  FOR ix = 0 TO (mapSizeX - 1) ' Draw line of trees at top and bottom border
    map(ix, 0) = mObjTree
    map(ix, mapSizeY - 1) = mObjTree ' Bottom row
  NEXT

  FOR iy = 0 TO (mapSizeY - 1) ' Draw line of trees at top and bottom border
    map(0, iy) = mObjTree
    map(mapSizeX - 1, iy) = mObjTree ' Right row
  NEXT

  map(mapSizeX - 1, 10) = 0 ' Leave a space to walk out
  map(10, mapSizeY - 1) = 0 ' Leave a space to walk out

  ' TREES THROWN IN RANDOMLY

  map(mapSizeX - 1, 4) = mObjTree
  map(1, 5) = mObjTree
  map(5, 6) = mObjTree
  map(8, 8) = mObjTree
  map(4, 15) = mObjTree
  map(5, 19) = mObjTree
  map(15, 12) = mObjTree
  map(8, 19) = mObjTree
  map(18, 7) = mObjTree
  map(32, 9) = mObjTree
  map(34, 14) = mObjTree
  map(20, 25) = mObjTree

END SUB

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''
SUB clearMap ()

  ' This function just clears the map

  FOR iy = 0 TO mapSizeX
    FOR ix = 0 TO mapSizeY
      map(ix, iy) = 0
    NEXT ix
  NEXT iy

END SUB


'''''''''''''''''''''''''''''''''''''''''''''''''''''''
FUNCTION moveCheck (wTrueX, wTrueY) ' When calling, make sure the true position is passed through

  IF wTrueX < 0 OR wTrueY < 0 THEN EXIT FUNCTION ' Don't flag, just exit, could be walking off map

  IF map(wTrueX, wTrueY) >= barrierNum THEN
    moveCheck = 1
    EXIT FUNCTION
  END IF

  moveCheck = 0 '' return zero otherwise

END FUNCTION

''''''''''''''''''''''''''''''''''''''''''''''''''
''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB splitPos (wTrueX, wTrueY)

  ' This sub takes true map positions and splits them into map and screen positions
  ' We don't have to pass the variables, since true positions are global variables, but it is here for flexibility

  IF wTrueX < viewCenterPosX THEN ' If on the left side before the center point x
    mapPosX = 0 ' Then we know we don't need an offset
    hScrPosX = wTrueX
  ELSE ' If player is at center or near the right edge of the map

    IF wTrueX >= (mapSizeX - (viewSizeTilesX - viewCenterPosX)) THEN ' Near the right edge of the map

      mapPosX = (mapSizeX - (viewSizeTilesX)) ' Move the map offset as far as possible right
      hScrPosX = wTrueX - mapPosX
    ELSE ' If in the center area

      mapPosX = wTrueX - viewCenterPosX
      hScrPosX = viewCenterPosX
    END IF
  END IF

  '' Now on to Y values

  IF wTrueY < viewCenterPosY THEN
    mapPosY = 0 ' Then we know we don't need an offset
    hScrPosY = wTrueY
  ELSE ' If player is at center or near the top edge of the map

    IF wTrueY >= (mapSizeY - (viewSizeTilesY - viewCenterPosY)) THEN ' Near the bottom edge of the map

      mapPosY = mapSizeY - viewSizeTilesY ' Move the map offset as far as possible down
      hScrPosY = wTrueY - mapPosY
    ELSE ' If in the center area

      mapPosY = wTrueY - viewCenterPosY
      hScrPosY = viewCenterPosY
    END IF
  END IF

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB ZLOCATE (wx, wy)

  LOCATE wy + 1, wx + 1 ' The + 1 lets us locate text at zero, easier to use

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB ESCAPE (escapeCode)
  COLOR 15
  ' We're now using ZLOCATE instead of LOCATE
  ' Added some spaces above and below the text for visibility
  ZLOCATE 10, 5: PRINT "                              "
  ZLOCATE 10, 6: PRINT "PROGRAM ENDED WITH CODE:"; escapeCode; "    "
  ZLOCATE 10, 7: PRINT "                             "

  END ' SYSTEM would also work
END SUB



