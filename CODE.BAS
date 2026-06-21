#GRAPHICS SCREENSIZEX, 256
#GDOUBLE

CONST SCREENSIZEX = 288
CONST SCREENSIZEY = 176

' DEMO I: The map is now loaded from file. To make a map like, run the function createMap.
' Our new functions are fileMapLoad and fileMapSave, which work with the file _demo.map.
' Supporting function inputStr

CONST tNumBlank = 0 ' Graphic tile numbers
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
DIM SHARED bmpData(255, 511) AS _UNSIGNED _BYTE ' Graphic tile storage

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
COMMON SHARED barrierNum, lastKeyPress

'''' Visual setup ''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
_FULLSCREEN
SCREEN _NEWIMAGE(SCREENSIZEX, SCREENSIZEY, 13) ' The 13 mimics the SCREEN 13 mode which allows 256 colors
_FONT 8 ' QB64 specific command to ensure the font is 8 x 8 in this mode
''''''''''''''''''''''

editMode = 0 ' For this demo, we'll turn it on at the start

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

  createMap ' To create the map, uncomment this line and comment out fileMapLoad
  'fileMapLoad ' To load a map that exists, uncomment this line and comment out createMap

  createTiles
  initShadowMask

  DO '''' BEGIN MAIN LOOP, OUTER ''''

    clearShadows
    IF showShadows = 1 THEN
      addShadows
      clearShadows
    END IF

    DO '''' INNER LOOP ''''

      in$ = UCASE$(INKEY$)

      redrawAll ' Moved inside of the inner loops since there is both slow and fast input to process now
      _DISPLAYI

      ' It gets a little wonky here, but INKEY$ won't catch the keys every time. We'll
      ' call processInput if it didn't, to catch any quick presses that it missed. Then if INKEY$
      ' did catch it, we'll do that after the inner loop wraps up instead. Note that $INKEY is
      ' itself really slowing down our loop right now. In later revisions we can have the directional
      ' keys processed by the fast keyCheck routines, but then we'll need to find a way to slow it down.

      IF in$ = "" THEN processInput ("")

    LOOP UNTIL in$ <> ""

    CALL processInput(in$)

  LOOP ' Closing outer loop. Exit process is handled by processInput

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

SUB createMap ()

  clearMap

  ' Using hexadecimal notation &H to help visually align these calls, otherwise 10+ will be misaligned

  CALL setMapRow(&H00, "W WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
  CALL setMapRow(&H01, "W                 W$                   W")
  CALL setMapRow(&H02, "W WWWWW WWWWW W W WWWWWWWW WWWWW WWWWW W")
  CALL setMapRow(&H03, "W W     W   W W W    W     W   W WWWWW W")
  CALL setMapRow(&H04, "W W WWWWW W W W WWWWWW WWWWW W W       W")
  CALL setMapRow(&H05, "W W       W W W              W W WWW WWW")
  CALL setMapRow(&H06, "W WWWWWWWWW   W WWWWWWWW WWWWW   WWW WWW")
  CALL setMapRow(&H07, "W W       WWW     W   W                W")
  CALL setMapRow(&H08, "W W W W W W$W W W W W W                W")
  CALL setMapRow(&H09, "W                   W W                W")
  CALL setMapRow(&H0A, "WWWWWWW WWW WWWWWWW W W                W")
  CALL setMapRow(&H0B, "W     W W W W     W W W                W")
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


'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
SUB createTiles ()

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

SUB fileMapLoad

  fln$ = "_demo.map"
  rwVar$ = " " ' Necessary
  OPEN fln$ FOR BINARY AS #1
  IF LOF(1) = 0 THEN

    CLOSE #1
    KILL fln$
    CLS
    LOCATE 1, 1
    outStr$ = "File '" + fln$ + "' does not exist"

    ESCAPETEXT (outStr$)

  END IF

  '''' File is confirmed to exist, go on to load map

  FOR ii = 0 TO 15 ' Pull and discard 16 reserved bytes
    GET #1, , rwVar$ ' Load from file and do not keep first four bytes we have reserved, to move the file pointer forward
  NEXT

  FOR iy = 0 TO mapSizeY - 1 ' Load map data
    FOR ix = 0 TO mapSizeX - 1
      GET #1, , rwVar$

      wVal = ASC(rwVar$)

      map(ix, iy) = wVal
    NEXT
  NEXT

  CLOSE #1

END SUB ' fileMapLoad

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
SUB fileMapSave

  fln$ = "_demo.map"

  OPEN fln$ FOR BINARY AS #1

  FOR ii = 0 TO 15
    rwvar$ = CHR$(0) ' 16 byes, reserved
    PUT #1, , rwvar$
  NEXT

  FOR iy = 0 TO mapSizeY - 1
    FOR ix = 0 TO mapSizeX - 1

      IF map(ix, iy) < 255 THEN ' Make sure we didn't add a block of too high a value
        rwvar$ = CHR$(map(ix, iy))
      ELSE
        rwvar$ = CHR$(0) ' Be sure we didn't include anything more than tile 255 on the map to save
      END IF

      PUT #1, , rwvar$

    NEXT
  NEXT

  CLOSE #1

END SUB
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
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

FUNCTION inputStr$ (wx, wy) ' Input and locate for a string in one command

  LOCATE wy + 1, wx + 1
  INPUT wStr$

  inputStr$ = wStr$

END FUNCTION
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

FUNCTION keyCheck (wStr$) ' KeyCheck fast (Follow up with waitKeyRelease to use as slow option)
  wStr$ = UCASE$(wStr$) ' The character that's being checked for. Should be sent uppercase, but just in case
  ' since _KEYDOWN does not return a value, this function was made to poll for key presses and return the value pressed
  ' This function will also help keep track of the special codes that keyDown uses. Only the
  ' codes that have specifically been entered, plus a-z, A-Z (calculated by formula) will work.
  ' Instead of returning 1 that the key has been pressed, the function returns the value of the
  ' key pressed. if keyCheck(whatever$) works just fine, because it checks to see if the return is greater than zero

  ' For the keys that don't exit the program right away, this function stores to rVal instead
  ' of returning right away, to provide the option to put it into a global "last key pressed" variable at the end of the function

  IF wStr$ = "*" THEN ' * KEY
    IF _KEYDOWN(42) THEN
      keyCheck = 42
      EXIT FUNCTION
    END IF
  END IF

  IF wStr$ = "ESC" THEN ' Escape key
    IF _KEYDOWN(27) THEN
      keyCheck = 27
      EXIT FUNCTION
    END IF
  END IF

  ' Detect a-z, A-Z, matches ASCII
  IF LEN(wStr$) = 1 THEN ' Handles characters A-Z, uppercase A is 65
    wVal = ASC(wStr$)
    IF ((wVal >= 65) AND (wVal <= 90)) OR ((wVal >= 97) AND (wVal <= 122)) THEN
      IF _KEYDOWN(wVal) OR _KEYDOWN(wVal + 32) THEN rVal = wVal ' The +32 is for lowercase
    END IF
  END IF

  ' Arrow keys and number pad for controls (not used yet)
  IF wStr$ = "2" THEN '  OR IN$ = "2" OR IN$ = CHR$(0) + "P" THEN
    IF _KEYDOWN(50) OR _KEYDOWN(20480) THEN rVal = 50 ' KEY 2, KEY RIGHT
  END IF

  IF wStr$ = "4" THEN ' OR IN$ = "4" OR IN$ = CHR$(0) + "K" THEN
    IF _KEYDOWN(52) OR _KEYDOWN(19200) THEN rVal = 52 ' KEY 4, KEY LEFT
  END IF

  IF wStr$ = "6" THEN ' OR IN$ = "6" OR IN$ = CHR$(0) + "M" THEN
    IF _KEYDOWN(54) OR _KEYDOWN(19712) THEN rVal = 54 ' KEY 6, KEY RIGHT
  END IF

  IF wStr$ = "8" THEN ' 'OR IN$ = "8" OR IN$ = CHR$(0) + "H" THEN
    IF _KEYDOWN(56) OR _KEYDOWN(18432) THEN rVal = 56 ' KEY 8, KEY UP
  END IF

  ' \ key (right above enter on the keyboard)
  IF wStr$ = "\" THEN
    IF _KEYDOWN(124) OR _KEYDOWN(92) THEN rVal = 124
  END IF

  IF wStr$ = "<" THEN
    IF _KEYDOWN(60) OR _KEYDOWN(44) THEN rVal = 60
  END IF

  IF wStr$ = ">" THEN
    IF _KEYDOWN(62) OR _KEYDOWN(46) THEN rVal = 62
  END IF

  IF wStr$ = "ENT" THEN ' ENTER key
    IF _KEYDOWN(13) THEN rVal = 13
  END IF

  IF rVal <> 0 THEN lastKeyPress = rVal
  keyCheck = rVal ' Always returns uppercase equivalent

END FUNCTION


''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

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

  IF keyCheck("E") THEN ' Toggle edit mode

    IF editMode = 0 THEN
      editMode = 1
    ELSE
      editMode = 0
    END IF
    waitKeyRelease "E"
    EXIT SUB
  END IF

  IF keyCheck("D") THEN ' Toggle shadow mode
    IF showShadows = 0 THEN
      showShadows = 1
    ELSE
      showShadows = 0
    END IF
    waitKeyRelease "D" ' So it doesn't process too fast, loop back again, and switch right back on
    EXIT SUB
  END IF

  ' MOVE UP
  IF in$ = "8" OR in$ = CHR$(0) + "H" THEN
    ' If editMode = 1 then ff stays zero
    IF editMode = 0 THEN ff = moveCheck(hTruePosX, hTruePosY - 1)

    IF hTruePosY > 0 AND ff = 0 THEN hTruePosY = hTruePosY - 1
    EXIT SUB
  END IF

  ' MOVE LEFT
  IF in$ = "4" OR in$ = CHR$(0) + "K" THEN

    IF editMode = 0 THEN ff = moveCheck(hTruePosX - 1, hTruePosY)

    IF hTruePosX > 0 AND ff = 0 THEN hTruePosX = hTruePosX - 1
    EXIT SUB
  END IF

  ' MOVE RIGHT
  IF in$ = "6" OR in$ = CHR$(0) + "M" THEN

    IF editMode = 0 THEN ff = moveCheck(hTruePosX + 1, hTruePosY)

    IF hTruePosX < (mapSizeX - 1) AND ff = 0 THEN hTruePosX = hTruePosX + 1
    EXIT SUB
  END IF

  ' MOVE DOWN
  IF in$ = "2" OR in$ = CHR$(0) + "P" THEN

    IF editMode = 0 THEN ff = moveCheck(hTruePosX, hTruePosY + 1)

    IF hTruePosY < (mapSizeY - 1) AND ff = 0 THEN hTruePosY = hTruePosY + 1
    EXIT SUB
  END IF
  '''''''''''''''''''''''''''''''

  IF keyCheck("L") THEN
    COLOR 14
    ZLOCATE 8, 8: PRINT "          "
    ZLOCATE 8, 9: PRINT "LOADING FILE"
    ZLOCATE 8, 10: PRINT "          "

    fileMapLoad
    waitKeyRelease "L" ' Will call _DISPLAY to fix a bug where the text doesn't show
    EXIT SUB
  END IF

  IF keyCheck("S") THEN
    COLOR 14
    ZLOCATE 8, 8: PRINT "          "
    ZLOCATE 8, 9: PRINT "SAVING FILE"
    ZLOCATE 8, 10: PRINT "          "

    fileMapSave
    waitKeyRelease "S"
    EXIT SUB
  END IF

  IF keyCheck("H") THEN
    IF wrapHorizontal = 0 THEN
      wrapHorizontal = 1
    ELSE
      wrapHorizontal = 0
    END IF
    waitKeyRelease "H"
    EXIT SUB
  END IF

  IF keyCheck("V") THEN
    IF wrapVertical = 0 THEN
      wrapVertical = 1
    ELSE
      wrapVertical = 0
    END IF
    waitKeyRelease "V"
    EXIT SUB
  END IF

  ' Map editing

  IF keyCheck("ENT") THEN ' ENTER during edit mode, change map objects

    discard$ = INKEY$ ' Somehow fixes a bug that skips over input statements

    ZLOCATE 10, 9: PRINT "              " ' Space around input
    ZLOCATE 10, 10: PRINT "  TILENUM     "
    ZLOCATE 10, 11: PRINT "               "
    LINE (81, 72)-(191, 72), 1
    LINE (81, 92)-(191, 92), 1

    newTile$ = inputStr$(19, 10)

    newTile$ = UCASE$(LTRIM$(RTRIM$(newTile$)))

    SELECT CASE (newTile$)
      CASE "T": map(hTruePosX, hTruePosY) = mObjTree
      CASE "W": map(hTruePosX, hTruePosY) = mObjWall
      CASE "$": map(hTruePosX, hTruePosY) = mObjChest

      CASE ELSE
        '
        newTileVal = VAL(newTile$)
        '
        IF newTileVal > 255 OR newTile$ = "" THEN EXIT CASE ' Skip over
        '
        map(hTruePosX, hTruePosY) = newTileVal
    END SELECT
    waitKeyRelease "ENT"
    '
    EXIT SUB
  END IF ' Enter key when in editMode

  '''' Exit keys:
  IF keyCheck("ESC") OR keyCheck("*") THEN ' Slow key ESC, key *

    ESCAPETEXT "PROGRAM ENDED"

  END IF

END SUB ' processInput

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

  ' Draw hero on screen, stamp using drawTile (PSET function)
  drawTileToPlayfield (hScrPosX * 8), (hScrPosY * 8), tNumHero ' Draw hero

  drawTile textX * 8, 8 * 1, tNumHeart ' Draw heart
  ZLOCATE textX + 1, 1: PRINT "LIFE: 10"

  '''' Show game info ''''
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
  PRINT "MAKE WALLS"
  ZLOCATE textX, 14
  PRINT "SOLID AND"
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

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

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

    map(ii - 1, yrow) = wTile
  NEXT

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

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

END SUB
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

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

SUB waitKeyRelease (wKey$)

  '_DISPLAY ' _DISPLAY can mess with visual output not shown by it, so this goes here to
  '''''''''' get caught after L and S are used so the printed text stays on the screen

  DO
  LOOP UNTIL keyCheck(wKey$) = 0

END SUB

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
SUB ZLOCATE (wx, wy)
  LOCATE wy + 1, wx + 1
END SUB
'''''''''''''''''''''''''

SUB ESCAPE (code)
  COLOR 15
  ZLOCATE 10, 5: PRINT "                              "
  ZLOCATE 10, 6: PRINT "ENDED WITH CODE:"; code; "    "
  ZLOCATE 10, 7: PRINT "                             "

  END ' SYSTEM also works
END SUB

'''''''''''''''''''''''''
SUB ESCAPETEXT (wStr$)

  COLOR 15

  xPos = 1
  yPos = 5

  IF wStr$ = "" THEN wStr$ = "No text sent"

  ZLOCATE xPos, yPos: PRINT "                 "
  ZLOCATE xPos, yPos + 2: PRINT "                 " ' Print before text in case text wraps
  ZLOCATE xPos, yPos + 1: PRINT "  "; wStr$; " "

  END ' SYSTEM
END SUB
