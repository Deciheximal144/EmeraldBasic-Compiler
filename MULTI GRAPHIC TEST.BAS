'''' Graphics draw test
' Exercises #GRAPHICS + #GDOUBLE double-buffered drawing
' PSET, LINE (plain / B / BF), CIRCLE, and SIN/COS plotting
' Each scene draws to the back buffer, flips with _DISPLAY,
' then waits for SPACE before advancing

'#GRAPHICS 640, 480, "Graphics Draw Test"
'#GDOUBLE
SCREEN _NEWIMAGE(640, 480, 13), 1, 0 ' The 13 mimics the SCREEN 13 mode which allows 256 colors

CONST CYAN = 11
CONST GREEN = 10
CONST RED = 12
CONST YELLOW = 14
CONST MAGENTA = 13
CONST WHITE = 15

DIM SHARED myData(60, 24) AS LONG
DIM SHARED boxGraphic(1000) AS LONG
DIM SHARED tilePattern$

' Initialize the pattern string for the PAINT test
tilePattern$ = CHR$(10) + CHR$(10) + CHR$(2) + CHR$(2) + CHR$(10) + CHR$(10) + CHR$(2) + CHR$(2)
tilePattern$ = tilePattern$ + CHR$(2) + CHR$(2) + CHR$(10) + CHR$(10) + CHR$(2) + CHR$(2) + CHR$(10) + CHR$(10)

'''' Scene 1: PSET pixels and a SIN wave
CLS
LOCATE 2, 2
PRINT "SCENE 1: PSET pixels and a SIN wave"

FOR iy = 80 TO 160 STEP 8
  FOR ix = 40 TO 200 STEP 8
    PSET (ix, iy), GREEN
  NEXT
NEXT

FOR ix = 0 TO 639
  py = 320 + (SIN(ix / 30) * 60)
  PSET (ix, py), CYAN
NEXT

WaitSpace 1

'''' Scene 2: LINE outline (B), an X, filled (BF), and Solid PAINT
CLS
LOCATE 2, 2
PRINT "SCENE 2: LINE outline (B), an X, filled (BF), and Solid PAINT"

LINE (60, 80)-(260, 280), WHITE, B
PAINT (160, 180), 1, WHITE

LINE (60, 80)-(260, 280), YELLOW
LINE (60, 280)-(260, 80), YELLOW
LINE (360, 80)-(560, 280), RED, BF

WaitSpace 1

'''' Scene 3: native CIRCLE vs manual SIN/COS circle with Pattern PAINT
CLS
LOCATE 2, 2
PRINT "SCENE 3: native CIRCLE vs manual SIN/COS circle with Pattern PAINT"

CIRCLE (200, 260), 110, YELLOW
PAINT (200, 260), tilePattern$, YELLOW

CIRCLE (200, 260), 60, MAGENTA

FOR angle = 0 TO 6.28 STEP 0.04
  px = 470 + (COS(angle) * 110)
  py = 260 + (SIN(angle) * 110)
  PSET (px, py), GREEN
NEXT

WaitSpace 1

'''' Scene 4: POINT reading and redrawing (Cat Box)
' Tests point reading of both lines drawn on screen and text, by reading what is
' output with POINT and drawing it again
CLS
LOCATE 2, 2
PRINT "SCENE 4: POINT reading and redrawing (Cat Box)"
COLOR 10

' Use offsets to move the initial drawing down and right
' giving enough space to keep everything on screen and avoid text overlap
bOffX = 14
bOffY = 24

' Draw outer box
LINE (bOffX, bOffY)-(bOffX + 60, bOffY + 24), 15, B

' Draw inner box
LINE (bOffX + 2, bOffY + 2)-(bOffX + 58, bOffY + 22), 3, B

COLOR 10
' Print text inside the boxes, perfectly centered based on the new offsets
LOCATE 5, 4
PRINT "=^.^="

' Read the pixels of the shape and text we just drew using the offsets
FOR iy = 0 TO 24
  FOR ix = 0 TO 60
    myData(ix, iy) = POINT(ix + bOffX, iy + bOffY)
  NEXT
NEXT

startX = 128
startY = 80

' Draw those copied pixels lower on the screen
FOR iy = 0 TO 24
  FOR ix = 0 TO 60
    ptClr = myData(ix, iy)
    PSET (ix + startX, iy + startY), ptClr
  NEXT
NEXT

COLOR 15
LOCATE 16, 2
PRINT "IF SUCCESSFUL, CAT IN SOLID BOX APPEARS TWICE"

WaitSpace 1

'''' Scene 5: Viewports and scrolling text
CLS
LOCATE 2, 2
PRINT "SCENE 5: Viewports and scrolling text"

' Setup a graphics viewport in the middle with a nice dark blue background and light blue border
VIEW (100, 100)-(540, 300), 1, 9

' Draw some graphics. Because the SCREEN option was intentionally omitted, these coordinates
' draw perfectly relative to the viewport's top-left corner instead of the absolute screen
FOR ix = 10 TO 400 STEP 20
  CIRCLE (ix, 100), ix / 4, (ix - ((ix \ 15) * 15)) + 1
NEXT ix

' Setup a very narrow text viewport directly below the graphics window
' We restrict it to avoid overlapping the top page listing and bottom prompt
VIEW PRINT 40 TO 48

' Start dropping lines. Watch how the graphics box remains perfectly intact above
' while only the text scrolls within its confined viewing boundaries
FOR ix = 1 TO 30
  COLOR (ix - ((ix \ 14) * 14)) + 1
  PRINT "Scrolling text line inside the text viewport! Line:"; ix

  _DISPLAY

  timeGoal = TIMER + 0.1
  WHILE TIMER < timeGoal
  WEND
NEXT ix

' Restore normal operations
VIEW
VIEW PRINT

LOCATE 49, 2
COLOR 15
PRINT "Finished! Viewports are disabled."

WaitSpace 1

'''' Scene 6: a combined drawing and GET / PUT graphics
CLS

' Create the sprite for the PUT test temporarily
LINE (10, 10)-(50, 50), 12, BF
LINE (20, 20)-(40, 40), 9, BF
GET (10, 10)-(50, 50), boxGraphic()
CLS

LOCATE 2, 2
PRINT "SCENE 6: a combined drawing and GET / PUT graphics"

LINE (0, 400)-(639, 400), WHITE
CIRCLE (520, 110), 50, YELLOW
LINE (180, 260)-(340, 400), GREEN, B
LINE (180, 260)-(260, 200), RED
LINE (260, 200)-(340, 260), RED

FOR ix = 0 TO 63
  px = ix * 10
  py = 80 + (SIN(ix / 4) * 30)
  PSET (px, py), WHITE
NEXT

' Draw background lines to test XOR color mixing
FOR ix = 400 TO 620 STEP 10
  LINE (ix, 220)-(ix, 360), 8
NEXT

' Place graphic using PSET and XOR to show collision and mixing
PUT (420, 240), boxGraphic(), PSET
PUT (500, 240), boxGraphic(), XOR
PUT (520, 260), boxGraphic(), XOR

LOCATE 25, 53
PRINT "PSET PUT"
LOCATE 25, 63
PRINT "XOR PUT"

LOCATE 22, 2
PRINT "All graphics scenes complete"

LOCATE 51 ' So the press any key to continue text appears at the bottom
END

SUB WaitSpace (withText)
  IF withText = 1 THEN
    LOCATE 52, 2
    PRINT "Press SPACE for the next test... "
    _DISPLAY
  END IF
  DO
    kk$ = INKEY$
  LOOP UNTIL kk$ = " "
END SUB ' WaitSpace

''''''''''''

