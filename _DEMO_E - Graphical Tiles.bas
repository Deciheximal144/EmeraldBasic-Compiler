' DEMO E: In this demo, we add graphical tiles that are drawn with pixels.
' setTilePixelRow and createTiles, drawTile, and drawTileToPlayfield are new functions for that
' Horizontal and vertical wrap controls are added - press H or V to toggle
' None of our tile are actually big enough to wrap past the 8 pixel mark presently.

' As a demonstration, the game is capable of either using GET and PUT to store images in
' tileImg, or to draw the images pixel by pixel using PSET and BMPdata. The GET and PUT
' are considered outdated commands by QBASIC64 PE. Switching to the newer _PUTIMAGE is an option,
' but in the next demo we'll continue with PSET only.

' We'll need some constants to help us remember what image tiles are what.
' Note that these are not the same as the map object constants.

CONST SCREENSIZEX = 376
CONST SCREENSIZEY = 256

CONST tNumBlank = 0 ' Graphic tile numbers
CONST tNumHero = 1
CONST tNumHeart = 2
CONST tNumChest = 3
CONST tNumTree = 6

CONST mObjTree = 16
CONST mObjChest = 17

CONST tileStep = 66 ' (8 x 8) + 2 for header, according to help instructions

CONST viewStartPixelsX = 16 ' Where the playfield starts on the screen
CONST viewStartPixelsY = 8 '' Now in pixels instead of tiles, moved into constants

'''' Global arrays
DIM SHARED map(120, 120)
DIM SHARED tileImg(6000) ' Graphic tile storage for GET / PUT (archaic)
DIM SHARED bmpData(256, 512) AS _UNSIGNED _BYTE ' This is the main way we will store our images in the future

'''' Global variables

' These view variables define the pixels of the playfield, they are global variables
' instead of constants because I may want to load them from a file later

COMMON SHARED viewCenterPosX: viewCenterPosX = 15 ' Center position of view window
COMMON SHARED viewCenterPosY: viewCenterPosY = 11 ' In 8-pixel tiles

COMMON SHARED viewSizeTilesX: viewSizeTilesX = (viewCenterPosX * 2) + 1 ' Farthest location right on the playscreen
COMMON SHARED viewSizeTilesY: viewSizeTilesY = (viewCenterPosY * 2) + 1 ' Farthest location down on the playscreen

COMMON SHARED wrapHorizontal, wrapVertical ' Defaults to zero

COMMON SHARED hTruePosX, hTruePosY, hScrPosX, hScrPosY, mapSizeX, mapSizeY, mapPosX, mapPosY
COMMON SHARED barrierNum, editMode

'''' Visual setup ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
_FULLSCREEN
SCREEN _NEWIMAGE(SCREENSIZEX, SCREENSIZEY, 13) ' The 13 mimics the SCREEN 13 mode which allows 256 colors
_FONT 8 ' QB64 specific command to ensure the font is 8 x 8 in this mode
''''''''''''''''''''''

editMode = 0

mapSizeX = 40
mapSizeY = 32

hTruePosX = 5 ' These are split into screen positions and map positions later
hTruePosY = 5

barrierNum = 16 ' If tile numbers are higher than this, the player can't move through them


'''''' I like to set the initial values for the global (COMMON SHARED) variables here,
'''''' then call initialization subroutines in the main function

CALL a_main

END ' When the a_Main subroutine exits, it returns here, which ends the program. SYSTEM would also work.

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB a_main () ' Main subroutine of our program

  createtiles
  createMap

  DO '''' BEGIN MAIN LOOP, OUTER ''''

    redrawAll

    DO '''' INNER LOOP ''''

      IN$ = INKEY$

    LOOP UNTIL IN$ <> ""

    IN$ = UCASE$(IN$)

    CALL processInput(IN$)

  LOOP UNTIL IN$ = "Q" OR IN$ = "*" OR ASC(IN$) = 27 ' ESC, outer loops ends, exits program

END SUB ' a_Main

''''''''''''''''''''''''
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
  map(32, 16) = mObjChest

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB clearMap ()

  ' This function just clears the map

  FOR iy = 0 TO mapSizeX
    FOR ix = 0 TO mapSizeY
      map(ix, iy) = 0
    NEXT ix
  NEXT iy

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB createtiles () ' Draw pixel graphics

  ' Our tiles are set up for 8 x 8 pixels. For now, we will only fill the first few
  ' tiles, which occupy the top 8 pixels of our 256 x 512 bitmap, in the upper left corner.
  ' Later we could set up to pull from a bitmap

  ' Also demonstrated is how to grab the images using GET, for storage in the tileImg array

  GET (0, 0)-(8 - 1, 8 - 1), tileImg(tileStep * tNumBlank) ' Get blank tile

  CLS

  CALL setTilePixelRow(tNumHero, 0, " FFFFF  ") ' Space will equally interpret as zero
  CALL setTilePixelRow(tNumHero, 1, " F   F  ")
  CALL setTilePixelRow(tNumHero, 2, " FFFFF  ")
  CALL setTilePixelRow(tNumHero, 3, "   F    ")
  CALL setTilePixelRow(tNumHero, 4, " FFFFF  ")
  CALL setTilePixelRow(tNumHero, 5, "   F    ")
  CALL setTilePixelRow(tNumHero, 6, "  F F   ")
  CALL setTilePixelRow(tNumHero, 7, " F   F  ")

  GET (0, 0)-(8 - 1, 8 - 1), tileImg(tileStep * tNumHero) ' Get player hero tile

  CLS ' Clears the screen and draws a new tile to GET. This happens so fast the player is unlikely
  ''''' to notice it at the beginning of the program

  CALL setTilePixelRow(tNumHeart, 0, " FF FF  ")
  CALL setTilePixelRow(tNumHeart, 1, "F44F44F ")
  CALL setTilePixelRow(tNumHeart, 2, "F44444F ")
  CALL setTilePixelRow(tNumHeart, 3, "F44444F ")
  CALL setTilePixelRow(tNumHeart, 4, " F444F  ")
  CALL setTilePixelRow(tNumHeart, 5, "  F4F   ")
  CALL setTilePixelRow(tNumHeart, 6, "   F    ")
  CALL setTilePixelRow(tNumHeart, 7, "        ")

  '' Life heart

  GET (0, 0)-(8 - 1, 8 - 1), tileImg(tileStep * tNumHeart)

  CLS

  CALL setTilePixelRow(tNumChest, 0, " 66666 ")
  CALL setTilePixelRow(tNumChest, 1, "6     6")
  CALL setTilePixelRow(tNumChest, 2, "6     6")
  CALL setTilePixelRow(tNumChest, 3, "6666666")
  CALL setTilePixelRow(tNumChest, 4, "6 888 6")
  CALL setTilePixelRow(tNumChest, 5, "6  8  6")
  CALL setTilePixelRow(tNumChest, 6, "6     6")
  CALL setTilePixelRow(tNumChest, 7, "6666666")


  GET (0, 0)-(8 - 1, 8 - 1), tileImg(tileStep * tNumChest)

END SUB ' CreateTiles
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB drawTile (wPosX, wPosY, wTile) ' Draw an 8 x 8 pixel tile
  ' Can draw anywhere on the screen

  ' Split wTile into X and Y positions for our 8 x 8 tiles
  offsetY = wTile \ 16 ' Shift right four bits
  offsetX = wTile AND 15 ' Drop high four bits

  FOR iy = 0 TO 7
    FOR ix = 0 TO 7
      drawPosX = (wPosX + ix) ' Since they will be used several times
      drawPosY = (wPosY + iy)

      PSET (drawPosX, drawPosY), bmpData((offsetX * 8) + ix, (offsetY * 8) + iy)

    NEXT
  NEXT
END SUB ' drawTile
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB drawTileToPlayfield (wPosX, wPosY, wTile) ' Draw an 8 x 8 pixel tile
  ' This function only will draw inside the gameplay area
  ' Anything more than 512 will draw to the left

  ' Split wTile into X and Y positions for our 8 x 8 tiles
  offsetY = wTile \ 16 ' Shift right four bits
  offsetX = wTile AND 15 ' Drop high four bits

  FOR iy = 0 TO 7
    FOR ix = 0 TO 7
      drawPosX = (wPosX + ix) ' Since they will be used several times
      drawPosY = (wPosY + iy)

      ' Wrapping, if pixel is too far over, move it back to the other side
      IF wrapHorizontal = 1 AND drawPosX > (viewSizeTilesX * 8) - 1 THEN drawPosX = drawPosX - (viewSizeTilesX * 8)
      IF wrapVertical = 1 AND drawPosY > (viewSizeTilesY * 8) - 1 THEN drawPosY = drawPosY - (viewSizeTilesY * 8)

      IF drawPosX > 0 AND drawPosY > 0 AND drawPosX < viewSizeTilesX * 8 AND drawPosY < viewSizeTilesY * 8 THEN
        PSET (viewStartPixelsX + drawPosX, viewStartPixelsY + drawPosY), bmpData((offsetX * 8) + ix, (offsetY * 8) + iy)
      END IF
    NEXT
  NEXT
END SUB ' drawTileToPlayfield
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

FUNCTION moveCheck (wTrueX, wTrueY) ' Make sure true position is passed off

  IF wTrueX < 0 OR wTrueY < 0 THEN EXIT FUNCTION ' Don't flag, just exit, could be walking off map

  IF map(wTrueX, wTrueY) >= barrierNum THEN
    moveCheck = 1
    EXIT FUNCTION
  END IF

  moveCheck = 0 '' return zero otherwise

END FUNCTION

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB processInput (in$) ' Process keyboard input

  IF in$ = "E" THEN
    IF editMode = 0 THEN
      editMode = 1
    ELSE
      editMode = 0
    END IF
  END IF

  ' MOVE UP
  IF in$ = "8" OR in$ = CHR$(0) + "H" THEN
    ' If editMode = 1 then ff stays zero
    IF editMode = 0 THEN ff = moveCheck(hTruePosX, hTruePosY - 1)

    IF hTruePosY > 0 AND ff = 0 THEN hTruePosY = hTruePosY - 1
  END IF

  ' MOVE LEFT
  IF in$ = "4" OR in$ = CHR$(0) + "K" THEN

    IF editMode = 0 THEN ff = moveCheck(hTruePosX - 1, hTruePosY)

    IF hTruePosX > 0 AND ff = 0 THEN hTruePosX = hTruePosX - 1

  END IF

  ' MOVE RIGHT
  IF in$ = "6" OR in$ = CHR$(0) + "M" THEN

    IF editMode = 0 THEN ff = moveCheck(hTruePosX + 1, hTruePosY)

    IF hTruePosX < (mapSizeX - 1) AND ff = 0 THEN hTruePosX = hTruePosX + 1
  END IF

  ' MOVE DOWN
  IF in$ = "2" OR in$ = CHR$(0) + "P" THEN

    IF editMode = 0 THEN ff = moveCheck(hTruePosX, hTruePosY + 1)

    IF hTruePosY < (mapSizeY - 1) AND ff = 0 THEN hTruePosY = hTruePosY + 1
  END IF
  '''''''''''''''''''''''''''''''

  IF in$ = "H" THEN
    IF wrapHorizontal = 0 THEN
      wrapHorizontal = 1
    ELSE
      wrapHorizontal = 0
    END IF
  END IF

  IF in$ = "V" THEN
    IF wrapVertical = 0 THEN
      wrapVertical = 1
    ELSE
      wrapVertical = 0
    END IF
  END IF

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB redrawAll ()

  CLS

  ' Draw border around playfield area
  LINE (viewStartPixelsX - 1, viewStartPixelsY - 1)-(viewStartPixelsX + (viewSizeTilesX * 8), viewStartPixelsY + (viewSizeTilesY * 8)), 14, B

  CALL splitPos(hTruePosX, hTruePosY) ' Pass the true X and Y positions to be split into map and screen positions

  COLOR 2 ' Green
  ' DRAW TREES
  FOR iy = 0 TO (viewSizeTilesY - 1)
    FOR ix = 0 TO (viewSizeTilesX - 1)

      tempX = mapPosX + ix ' Makes it easier
      tempY = mapPosY + iy

      IF map(tempX, tempY) = mObjTree THEN ' Draw tree, character

        ZLOCATE ix + (viewStartPixelsX \ 8), iy + (viewStartPixelsY \ 8)
        PRINT CHR$(tNumTree);

      END IF

      ' Now we'll draw more than just trees. Here's a chest:
      IF map(mapPosX + ix, mapPosY + iy) = mObjChest THEN ' Draw chest
        ' Alternate PUT method:
        ' PUT (viewStartPixelsX + (ix * 8), viewStartPixelsY + (iy * 8)), tileImg(tileStep * tNumChest), PSET
        drawTileToPlayfield (ix * 8), (iy * 8), tNumChest

      END IF
    NEXT ix
  NEXT iy

  ' In case we want to change where the text shows on the X axis easily
  textX = viewSizeTilesX + (viewStartPixelsX \ 8) + 1
  COLOR 15 ' All text in our sidebar will be white

  '' Old way of drawing was:
  'ZLOCATE viewStartPixelsX + hScrPosX, viewStartPixelsY + hScrPosY
  'COLOR heroClr
  'PRINT CHR$(2); ' Show hero

  ' Images have been saved to store in two different methods. We'll use PUT for this first one
  ' and use the drawTile / PSET function for background tiles to demonstrate

  ' Draw hero on screen, stamp using PUT

  PUT (viewStartPixelsX + (hScrPosX * 8), viewStartPixelsY + (hScrPosY * 8)), tileImg(tileStep * tNumHero), PSET ' Draw hero
  ' Alternate method we could use:
  ' drawTileInFrame viewStartPixelsX + (hScrPosX * 8), viewStartPixelsY + (hScrPosY * 8), tNumHero ' draw hero

  ' Draw heart, an example of drawing using the drawTILE PSET function:
  '  PUT (8 * 35, 8 * 1), tileImg(tileStep * tNumHeart) ' draw heart
  drawTile textX * 8, 8 * 1, tNumHeart ' draw heart, if drawTileInFrame had been used, it wouldn't go outside the viewing area

  COLOR 15
  ZLOCATE textX + 1, 1: PRINT "LIFE: 10"

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

  ZLOCATE textX, 7 ' Lets us see what is stored in map() where the player is
  PRINT "@:";
  PRINT map(hTruePosX, hTruePosY)

  ZLOCATE textX, 9
  PRINT "Edit Mode:";
  IF editMode = 0 THEN
    PRINT "OFF"
  ELSE
    PRINT "ON"
  END IF

  ZLOCATE textX, 12
  PRINT "PRESS E TO"
  ZLOCATE textX, 13
  PRINT "TOGGLE SOLID"
  ZLOCATE textX, 14
  PRINT "OBJECTS"


  ZLOCATE textX, 22: PRINT "HWRAP:";
  IF wrapHorizontal = 1 THEN
    PRINT "ON"
  ELSE
    PRINT "OFF"
  END IF

  ZLOCATE textX, 23: PRINT "VWRAP:";
  IF wrapVertical = 1 THEN
    PRINT "ON"
  ELSE
    PRINT "OFF"
  END IF

END SUB


'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
SUB setTilePixelRow (wTile, starty, td$)

  ' Split wTile into X and Y positions for our 8 x 8 tiles
  offsetY = wTile \ 16 ' Shift right four bits
  offsetX = wTile AND 15 ' Drop high four bits

  FOR lp = 1 TO LEN(td$)
    wChar$ = MID$(td$, lp, 1)

    SELECT CASE wChar$ ' switch ' Check to see if a letter, if not it is assumed a number (bad letter will output zero)
      CASE "A": wClr = 10
      CASE "B": wClr = 11
      CASE "C": wClr = 12
      CASE "D": wClr = 13
      CASE "E": wClr = 14
      CASE "F": wClr = 15
      CASE ELSE: wClr = VAL(wChar$)

    END SELECT

    PSET (startx + lp - 1, starty), wClr ' Draw the pixel

    bmpData((offsetX * 8) + lp - 1, (offsetY * 8) + starty) = wClr

  NEXT

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

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
  LOCATE wy + 1, wx + 1
END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB ESCAPE (escapeCode)
  COLOR 15
  ZLOCATE 10, 5: PRINT "                              "
  ZLOCATE 10, 6: PRINT "PROGRAM ENDED WITH CODE:"; escapeCode; "    "
  ZLOCATE 10, 7: PRINT "                             "

  END ' SYSTEM would also work
END SUB





