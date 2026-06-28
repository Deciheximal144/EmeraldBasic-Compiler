' Demo G: Adding shadows. Press D to turn on and off the lights.
' A mask lets us define exactly where we want the shadows to be.

CONST SCREENSIZEX = 288
CONST SCREENSIZEY = 176

'''' Visual setup ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
_FULLSCREEN
SCREEN _NEWIMAGE(SCREENSIZEX, SCREENSIZEY, 13) ' The 13 mimics the SCREEN 13 mode which allows 256 colors
_FONT 8 ' QB64 specific command to ensure the font is 8 x 8 in this mode
''''''''''''''''''''''

CONST tNumBlank = 0
CONST tNumHero = 1
CONST tNumHeart = 2
CONST tNumChest = 3
CONST tNumWall = 219
CONST tNumTree = 6

CONST mObjTree = 16
CONST mObjChest = 17
CONST mObjWall = 18

CONST viewStartPixelsX = 16 ' Where the playfield starts on the screen
CONST viewStartPixelsY = 8 '' Now in pixels instead of tiles

'''' Global arrays
DIM SHARED map(120, 120)
DIM SHARED SHADOWS(40, 40) ' Value of 1 means in shadow, make sure this is as large as any screen shown
DIM SHARED SHADOWMASK(12, 12)
DIM SHARED bmpData(256, 512) AS _UNSIGNED _BYTE ' Graphic tile storage

'''' Global variables

' These view variables define the pixels of the playfield, they are global variables
' instead of constants because I may want to load them from a file later

COMMON SHARED viewCenterPosX: viewCenterPosX = 9 ' A little smaller now
COMMON SHARED viewCenterPosY: viewCenterPosY = 9

COMMON SHARED viewSizeTilesX: viewSizeTilesX = (viewCenterPosX * 2) + 1 ' Farthest location right on the playscreen
COMMON SHARED viewSizeTilesY: viewSizeTilesY = (viewCenterPosY * 2) + 1 ' Farthest location down on the playscreen

COMMON SHARED wrapHorizontal, wrapVertical ' Defaults to zero

COMMON SHARED editMode, showShadows
COMMON SHARED mapSizeX, mapSizeY, mapPosX, mapPosY
COMMON SHARED hTruePosX, hTruePosY, hScrPosX, hScrPosY
COMMON SHARED barrierNum


editMode = 0

mapSizeX = 40
mapSizeY = 32

hTruePosX = 5 ' These are split into screen positions and map positions later
hTruePosY = 3

barrierNum = 16 ' If tile numbers are higher than this, the player can't move through them

'''''' I like to set the initial values for the global (COMMON SHARED) variables here,
'''''' then call initialization subroutines in the main function

CALL a_main

END ' When the a_Main subroutine exits, it returns here, which ends the program. SYSTEM would also work.

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB a_main () ' Main subroutine of our program

  createtiles
  assignMap
  initShadowMask

  DO '''' BEGIN MAIN LOOP, OUTER ''''

    clearShadows
    IF showShadows = 1 THEN
      addShadows
      clearShadows
    END IF

    redrawAll

    DO '''' INNER LOOP ''''

      IN$ = INKEY$

    LOOP UNTIL IN$ <> ""

    IN$ = UCASE$(IN$)

    CALL processInput(IN$)

  LOOP UNTIL IN$ = "Q" OR IN$ = "*" OR ASC(IN$) = 27 ' ESC, outer loops ends, exits program

END SUB ' a_Main
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB addShadows ()

  FOR ix = 0 TO viewSizeTilesX - 1 ' Shadows is an array the size of the viewing array, not the map
    FOR iy = 0 TO viewSizeTilesY - 1
      SHADOWS(ix, iy) = 1
    NEXT
  NEXT

END SUB
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB assignMap ()

  clearMap

  ' Using hexadecimal notation &H to help visually align these calls, otherwise 10+ will be misaligned

  CALL setMapRow(&H00, "W WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
  CALL setMapRow(&H01, "W                 W$                   W")
  CALL setMapRow(&H02, "W WWWWW WWWWW W W WWWWWWWW WWWWW WWWWW W")
  CALL setMapRow(&H03, "W W     W   W W W    W     W   W WWWWW W")
  CALL setMapRow(&H04, "W W WWWWW W W W WWWWWW WWWWW W W       W")
  CALL setMapRow(&H05, "W W       W W W              W W WWW WWW")
  CALL setMapRow(&H06, "W WWWWWWWWW  W  WWWWWWWW WWWWW   WWW WWW")
  CALL setMapRow(&H07, "W W        W   WW    WW                W")
  CALL setMapRow(&H08, "W W WWWWWWW$WW    WW WW                W")
  CALL setMapRow(&H09, "W              WW W  WW                W")
  CALL setMapRow(&H0A, "WWWWWWW WWW WWWW  W WWW                W")
  CALL setMapRow(&H0B, "W     W W W W                          W")
  CALL setMapRow(&H0C, "W WWWWW W W W T T                      W")
  CALL setMapRow(&H0D, "W W   W W W                            W")
  CALL setMapRow(&H0E, "W W W W W W                            W")
  CALL setMapRow(&H0F, "W W W W W W                            W")
  CALL setMapRow(&H10, "W W W       W                        W W")
  CALL setMapRow(&H11, "W W WWW WWW                          W W")
  CALL setMapRow(&H12, "W   W W WWW                          W W")
  CALL setMapRow(&H13, "W W W W WWW WWWWWWWWWWWWWWWWWWWWWWWWWW W")
  CALL setMapRow(&H14, "W                                      W")
  CALL setMapRow(&H15, "W                                      W")
  CALL setMapRow(&H16, "W                                      W")
  CALL setMapRow(&H17, "W                                      W")
  CALL setMapRow(&H18, "W                                      W")
  CALL setMapRow(&H19, "W                                      W")
  CALL setMapRow(&H1A, "W                                      W")
  CALL setMapRow(&H1B, "W                                      W")
  CALL setMapRow(&H1C, "W                                      W")
  CALL setMapRow(&H1D, "W                                      W")
  CALL setMapRow(&H1E, "W                                      W")
  CALL setMapRow(&H1F, "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB clearMap ()

  ' This function just clears the map

  FOR iy = 0 TO mapSizeX
    FOR ix = 0 TO mapSizeY
      map(ix, iy) = 0
    NEXT ix
  NEXT iy

END SUB
''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB clearShadows ()

  CALL splitPos(hTruePosX, hTruePosY) ' Pass the true X and Y positions to be split into map and screen positions

  ' Now using hScrPosX and hScrPosY

  '' clear shadows around player as defined by shadowMask

  FOR iy = minZero(hScrPosY - 4) TO maxLimit(hScrPosY + 4, viewSizeTilesY - 1) ' Maxlimit is so they don't go past map array
    FOR ix = minZero(hScrPosX - 4) TO maxLimit(hScrPosX + 4, viewSizeTilesX - 1) ' Maxlimit is so they don't go past map array

      xShadow = ix - (hScrPosX - 4)
      yShadow = iy - (hScrPosY - 4)

      IF SHADOWMASK(xShadow, yShadow) = 1 THEN
        SHADOWS(ix, iy) = 0 ' Set to no shadow
      END IF
    NEXT
  NEXT

  '' Next step, move forward and clear anything in visible range

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB createtiles ()

  ' Our tiles are set up for 8 x 8 pixels. For now, we will only fill the first few
  ' tiles, which occupy the top 8 pixels of our 256 x 512 bitmap, in the upper left corner.
  ' Later we could set up to pull from a bitmap

  CALL setTilePixelRow(tNumHero, 0, " FFFFF  ") ' Space will equally interpret as zero
  CALL setTilePixelRow(tNumHero, 1, " F   F  ")
  CALL setTilePixelRow(tNumHero, 2, " FFFFF  ")
  CALL setTilePixelRow(tNumHero, 3, "   F    ")
  CALL setTilePixelRow(tNumHero, 4, " FFFFF  ")
  CALL setTilePixelRow(tNumHero, 5, "   F    ")
  CALL setTilePixelRow(tNumHero, 6, "  F F   ")
  CALL setTilePixelRow(tNumHero, 7, " F   F  ")

  CALL setTilePixelRow(tNumHeart, 0, " FF FF  ") ' Save heart
  CALL setTilePixelRow(tNumHeart, 1, "F44F44F ")
  CALL setTilePixelRow(tNumHeart, 2, "F44444F ")
  CALL setTilePixelRow(tNumHeart, 3, "F44444F ")
  CALL setTilePixelRow(tNumHeart, 4, " F444F  ")
  CALL setTilePixelRow(tNumHeart, 5, "  F4F   ")
  CALL setTilePixelRow(tNumHeart, 6, "   F    ")
  CALL setTilePixelRow(tNumHeart, 7, "        ")

  CALL setTilePixelRow(tNumChest, 0, " 66666 ") ' Chest
  CALL setTilePixelRow(tNumChest, 1, "6     6")
  CALL setTilePixelRow(tNumChest, 2, "6     6")
  CALL setTilePixelRow(tNumChest, 3, "6666666")
  CALL setTilePixelRow(tNumChest, 4, "6 888 6")
  CALL setTilePixelRow(tNumChest, 5, "6  8  6")
  CALL setTilePixelRow(tNumChest, 6, "6     6")
  CALL setTilePixelRow(tNumChest, 7, "6666666")

END SUB
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

      IF drawPosX >= 0 AND drawPosY >= 0 AND drawPosX < viewSizeTilesX * 8 AND drawPosY < viewSizeTilesY * 8 THEN
        PSET (viewStartPixelsX + drawPosX, viewStartPixelsY + drawPosY), bmpData((offsetX * 8) + ix, (offsetY * 8) + iy)
      END IF
    NEXT
  NEXT
END SUB ' drawTileToPlayfield
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB initShadowMask ' At present, just applies shadowMask

  ' Guaranteed visible area
  '   ***
  '  *****
  ' *******
  ' ***H***
  ' *******
  '  *****
  '   ***
  ' 0123456

  CALL initShadowMaskRow(0, "  11111")
  CALL initShadowMaskRow(1, " 1111111")
  CALL initShadowMaskRow(2, "111111111")
  CALL initShadowMaskRow(3, "111111111")
  CALL initShadowMaskRow(4, "1111H1111")
  CALL initShadowMaskRow(5, "111111111")
  CALL initShadowMaskRow(6, "111111111")
  CALL initShadowMaskRow(7, " 1111111")
  CALL initShadowMaskRow(8, "  11111")

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB initShadowMaskRow (starty, td$)

  FOR ii = 1 TO LEN(td$)
    wChar$ = MID$(td$, ii, 1)
    IF wChar$ = "H" THEN
      wVal = 1
    ELSE
      wVal = VAL(wChar$)
    END IF
    SHADOWMASK(ii - 1, starty) = VAL(wChar$)
  NEXT
END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

FUNCTION maxLimit (wVal, limit)

  IF wVal < limit THEN
    maxLimit = wVal
  ELSE
    maxLimit = limit
  END IF

END FUNCTION
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

FUNCTION minLimit (wVal, limit)

  IF wVal > limit THEN
    minLimit = wVal
  ELSE
    minLimit = limit
  END IF

END FUNCTION
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

FUNCTION minZero (wVal)

  IF wVal <= 0 THEN
    minZero = 0
  ELSE
    minZero = wVal
  END IF

END FUNCTION
''''''''''''''''''''''''''''''''''''''''''''''''''''''

FUNCTION moveCheck (wTrueX, wTrueY) ' Make sure true position is passed off

  IF wTrueX < 0 OR wTrueY < 0 THEN EXIT FUNCTION ' Don't flag, just exit, could be walking off map

  IF map(wTrueX, wTrueY) >= barrierNum THEN
    moveCheck = 1
    EXIT FUNCTION
  END IF

  moveCheck = 0 '' return zero otherwise

END FUNCTION

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
SUB processInput (in$) ' Process keyboard input

  IF in$ = "E" THEN
    IF editMode = 0 THEN
      editMode = 1
    ELSE
      editMode = 0
    END IF
  END IF

  IF in$ = "D" THEN ' D for darkness, we'll need S later
    IF showShadows = 0 THEN
      showShadows = 1
    ELSE
      showShadows = 0
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


'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

SUB redrawAll ()

  CLS

  ' Draw border around playfield area
  LINE (viewStartPixelsX - 1, viewStartPixelsY - 1)-(viewStartPixelsX + (viewSizeTilesX * 8), viewStartPixelsY + (viewSizeTilesY * 8)), 14, B

  CALL splitPos(hTruePosX, hTruePosY) ' Pass the true X and Y positions to be split into map and screen positions

  ' redrawall

  ' DRAW BACKGROUND
  FOR iy = 0 TO (viewSizeTilesY - 1)
    FOR ix = 0 TO (viewSizeTilesX - 1)

      ' We apply shadows by skipping ahead if shadow is active, avoiding a long IF nest
      IF showShadows = 1 AND SHADOWS(ix, iy) = 1 THEN GOTO shadowSkip ' To this label, below

      tempX = mapPosX + ix ' Makes it easier
      tempY = mapPosY + iy

      IF map(tempX, tempY) = mObjTree THEN ' Draw characters like trees and walls first

        COLOR 2
        ZLOCATE ix + (viewStartPixelsX \ 8), iy + (viewStartPixelsY \ 8)
        PRINT CHR$(tNumTree);

      END IF

      IF map(tempX, tempY) = mObjWall THEN ' Draw characters like trees and walls first

        ZLOCATE ix + (viewStartPixelsX \ 8), iy + (viewStartPixelsY \ 8)
        COLOR 15
        PRINT CHR$(tNumWall);

      END IF

      ' If a chest:
      IF map(mapPosX + ix, mapPosY + iy) = mObjChest THEN ' Draw chest
        drawTileToPlayfield (ix * 8), (iy * 8), tNumChest
      END IF

      shadowSkip:
    NEXT ix
  NEXT iy

  ' In case we want to change where the text shows on the X axis easily
  textX = viewSizeTilesX + (viewStartPixelsX \ 8) + 1
  COLOR 15 ' All text in our sidebar will be white

  ' Draw hero on screen
  drawTileToPlayfield (hScrPosX * 8), (hScrPosY * 8), tNumHero ' Draw hero

  drawTile textX * 8, 8 * 1, tNumHeart ' Draw heart
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

  ZLOCATE textX, 10
  PRINT "Shadows:";
  IF showShadows = 0 THEN
    PRINT "OFF"
  ELSE
    PRINT "ON"
  END IF

  ZLOCATE textX, 12
  PRINT "PRESS E TO"
  ZLOCATE textX, 13
  PRINT "TOGGLE SOLID"
  ZLOCATE textX, 14
  PRINT "OBJECTS AND"
  ZLOCATE textX, 15
  PRINT "D TO TOGGLE"
  ZLOCATE textX, 16
  PRINT "SHADOWS"

  ZLOCATE textX, 18: PRINT "HWRAP:";
  IF wrapHorizontal = 1 THEN
    PRINT "ON"
  ELSE
    PRINT "OFF"
  END IF

  ZLOCATE textX, 19: PRINT "VWRAP:";
  IF wrapVertical = 1 THEN
    PRINT "ON"
  ELSE
    PRINT "OFF"
  END IF

END SUB ' redrawAll

'''''''''''''''''''''''''''''''''''''''''''

SUB setMapRow (yrow, rd$)

  FOR ii = 1 TO LEN(rd$)

    wChar$ = MID$(rd$, ii, 1)

    SELECT CASE wChar$ ' switch ' Check to see if a letter, if not it is assumed a number (bad letter will output zero)
      CASE "A": wTile = 10
      CASE "B": wTile = 11
      CASE "C": wTile = 12
      CASE "D": wTile = 13
      CASE "E": wTile = 14
      CASE "F": wTile = 15
      CASE "W": wTile = mObjWall
      CASE "T": wTile = mObjTree
      CASE "$": wTile = mObjChest
      CASE ELSE: wTile = VAL(MID$(rd$, lp, 1))

    END SELECT

    'wTile = VAL(MID$(rd$, ii, 1))

    IF wTile = 1 THEN wTile = mObjWall
    IF wTile = 2 THEN wTile = mObjChest

    map(ii - 1, yrow) = wTile
  NEXT

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

    ' We now draw directly to bmpData by storing in the array

    bmpData((offsetX * 8) + lp - 1, (offsetY * 8) + starty) = wClr

  NEXT

END SUB ' setTilePixelRow

''''''''''''''''''''''''
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
''''''''''''''''''''''''

SUB ZLOCATE (wx, wy)

  LOCATE wy + 1, wx + 1

END SUB
''''''''''''''''''''''''

SUB ESCAPE (code)

  COLOR 15
  ZLOCATE 10, 5: PRINT "                              "
  ZLOCATE 10, 6: PRINT "ENDED WITH CODE:"; code; "    "
  ZLOCATE 10, 7: PRINT "                             "

  END ' SYSTEM also works

END SUB
