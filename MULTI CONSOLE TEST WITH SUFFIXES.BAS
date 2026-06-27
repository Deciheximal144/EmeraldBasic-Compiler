' ============================================================
' CONSOLE PRINT & MATH TEST
' Tests printing and math: PRINT formatting, integer & float
' arithmetic, operator precedence, explicit casts, trig
' intrinsics, and AND/OR/NOT logic.
' Each test prints EXPECTED values, then waits for ENTER.
' ============================================================

COMMON SHARED valMin AS _INTEGER64
COMMON SHARED valLarge AS _INTEGER64

CLS
PRINT "=============================================="
PRINT "         CONSOLE PRINT & MATH TEST"
PRINT "=============================================="
PRINT ""
PRINT "9 test pages will run. Each prints its EXPECTED"
PRINT "values so you can verify the output."
WaitEnter

' ----- PAGE 1: PRINT FORMATTING & INTEGER ARITHMETIC -----
CLS
PRINT "[ PAGE 1: PRINT FORMATTING & INTEGER ARITHMETIC ]"
PRINT ""
PRINT "Plain string line."
PRINT "Semicolon join:"; 1; 2; 3; " (EXPECTED: 1  2  3)"
aa$ = "Hello"
bb$ = "World"
PRINT "Concatenation: "; aa$ + " " + bb$; " (EXPECTED: Hello World)"
PRINT "CHR$(65)+CHR$(66)+CHR$(67): "; CHR$(65) + CHR$(66) + CHR$(67); " (EXPECTED: ABC)"
PRINT "Quote via CHR$(34): "; CHR$(34); "quoted"; CHR$(34)
PRINT ""
ai% = 7
bi% = 3
PRINT "7 + 3 ="; ai% + bi%; " (EXPECTED: 10)"
PRINT "7 - 3 ="; ai% - bi%; " (EXPECTED: 4)"
PRINT "7 * 3 ="; ai% * bi%; " (EXPECTED: 21)"
PRINT "100 \ 8 ="; 100 \ 8; " (EXPECTED: 12)"
PRINT "17 \ 5 ="; 17 \ 5; " (EXPECTED: 3)"
WaitEnter

' ----- PAGE 2: FLOATING-POINT ARITHMETIC & OPERATOR PRECEDENCE -----
CLS
PRINT "[ PAGE 2: FLOATING-POINT ARITHMETIC & OPERATOR PRECEDENCE ]"
PRINT ""
PRINT "3.0 / 2.0 ="; 3.0 / 2.0; " (EXPECTED: 1.5)"
PRINT "7.0 / 2.0 ="; 7.0 / 2.0; " (EXPECTED: 3.5)"
PRINT "5.5 * 2.0 ="; 5.5 * 2.0; " (EXPECTED: 11)"
PRINT "10.0 / 3.0 ="; 10.0 / 3.0; " (EXPECTED: ~3.333333)"
myD# = 9999.99 * 2.5
PRINT "9999.99 * 2.5 ="; myD#; " (EXPECTED: 24999.975)"
PRINT ""
PRINT "2 + 3 * 4 ="; 2 + 3 * 4; " (EXPECTED: 14)"
PRINT "(2 + 3) * 4 ="; (2 + 3) * 4; " (EXPECTED: 20)"
PRINT "20 - 5 - 3 ="; 20 - 5 - 3; " (EXPECTED: 12)"
PRINT "2 * 3 + 4 * 5 ="; 2 * 3 + 4 * 5; " (EXPECTED: 26)"
PRINT "2 + 3 * 4 - 1 ="; 2 + 3 * 4 - 1; " (EXPECTED: 13)"
WaitEnter

' ----- PAGE 3: EXPLICIT CASTS, TRIG & INTRINSIC MATH -----
CLS
PRINT "[ PAGE 3: EXPLICIT CASTS, TRIG & INTRINSIC MATH ]"
PRINT ""
PRINT "(QB64 CINT/CLNG round to nearest; .5 ties go to even)"
PRINT ""
floatVal! = 15.99
PRINT "CINT(15.99) ="; CINT(floatVal!); " (EXPECTED: 16)"
negFloat# = -42.8
PRINT "CLNG(-42.8) ="; CLNG(negFloat#); " (EXPECTED: -43)"
wholeNum% = 255
PRINT "CSNG(255)   ="; CSNG(wholeNum%); " (EXPECTED: 255)"
bigNum& = 987654321
PRINT "CDBL(987654321) ="; CDBL(bigNum&); " (EXPECTED: 987654321)"
PRINT "CINT(10.75)+CINT(5.5) ="; CINT(10.75) + CINT(5.5); " (EXPECTED: 17)"
PRINT ""
PRINT "ATN(1) * 4 (Pi) ="; ATN(1) * 4; " (EXPECTED: ~3.141593)"
PRINT "SIN(0) ="; SIN(0); " (EXPECTED: 0)"
PRINT "COS(0) ="; COS(0); " (EXPECTED: 1)"
PRINT "SIN(ATN(1)*2) (Pi/2) ="; SIN(ATN(1) * 2); " (EXPECTED: 1)"
PRINT "22.0 / 7.0 ="; 22.0 / 7.0; " (EXPECTED: ~3.142857)"
WaitEnter

' ----- PAGE 4: COMPARISON & LOGIC -----
CLS
PRINT "[ PAGE 4: COMPARISON & LOGIC ]"
PRINT ""
PRINT "Each line should print PASS:"
PRINT ""
pp% = 5
qq% = 10
IF pp% = 5 AND qq% = 10 THEN
  PRINT "AND test: PASS"
ELSE
  PRINT "AND test: FAIL"
END IF
IF pp% = 99 OR qq% = 10 THEN
  PRINT "OR test:  PASS"
ELSE
  PRINT "OR test:  FAIL"
END IF
IF NOT (pp% = 99) THEN
  PRINT "NOT test: PASS"
ELSE
  PRINT "NOT test: FAIL"
END IF
IF (pp% < qq%) AND (pp% <> qq%) THEN
  PRINT "Combined comparison test: PASS"
ELSE
  PRINT "Combined comparison test: FAIL"
END IF

' String comparison logic test
str1$ = "APPLE"
str2$ = "Zebra"
IF str1$ < str2$ THEN
  PRINT "String compare test: PASS"
ELSE
  PRINT "String compare test: FAIL"
END IF
WaitEnter

' ----- PAGE 5: 64-BIT INTEGER BOUNDARIES -----
CLS
PRINT "[ PAGE 5: 64-BIT INTEGER BOUNDARIES & RESULTS ]"
PRINT ""

' A value safely larger than the 32-bit signed max of 2,147,483,647
valLarge = 8589934592

' Construct INT64_MIN safely to test the two's complement boundary
valMin = -9223372036854775807
valMin = valMin - 1

PRINT "1. PRINT Large INT64           2. STR$() Large INT64"
PRINT "EXPECTED:  8589934592          EXPECTED:  8589934592"
PRINT "ACTUAL  : "; valLarge; TAB(32); "ACTUAL  : "; STR$(valLarge)
PRINT ""

PRINT "3. PRINT INT64_MIN             4. STR$() INT64_MIN"
PRINT "EXPECTED: -9223372036854775808 EXPECTED: -9223372036854775808"
PRINT "ACTUAL  : "; valMin; TAB(32); "ACTUAL  : "; STR$(valMin)
PRINT ""

PRINT "=================================================="
PRINT "RESULTS ANALYSIS:"
PRINT "If Test 1 or 2 shows '0' or a small number, the 64-bit"
PRINT "value was truncated to 32-bit."
PRINT "If Test 3 or 4 shows '( ' or garbage, the TC_NEG bug"
PRINT "is still present on the absolute minimum integer."
PRINT "If EXPECTED matches ACTUAL perfectly, fixes are successful!"
WaitEnter

' ----- PAGE 6: EXTENDED STRINGS & RECURSION -----
CLS
PRINT "[ PAGE 6: EXTENDED STRINGS & RECURSION ]"
PRINT ""
ss$ = "Emerald"
PRINT "LEFT$(Emerald,3)  = "; LEFT$(ss$, 3); " (EXPECTED: Eme)"
PRINT "RIGHT$(Emerald,4) = "; RIGHT$(ss$, 4); " (EXPECTED: rald)"
PRINT "MID$(Emerald,3,2) = "; MID$(ss$, 3, 2); " (EXPECTED: er)"
PRINT "UCASE$(Emerald)   = "; UCASE$(ss$); " (EXPECTED: EMERALD)"
PRINT "HEX$(255)         = "; HEX$(255); " (EXPECTED: FF)"
PRINT "SPACE$(3)"
PRINT "EXPECTED: [   ]"
PRINT "ACTUAL  : ["; SPACE$(3); "]"
PRINT ""
PRINT "=================================================="
PRINT "RECURSIVE INTERMEDIATE REPRESENTATION BUG TESTING"
PRINT "Testing Bug 1: Recursive TIRA Clobbering"
PRINT ""
PRINT "recurseMath(2) evaluates as:"
PRINT "= (2 * 10) + recurseMath(1)"
PRINT "= 20 + ((1 * 10) + recurseMath(0))"
PRINT "= 20 + 11 = 31"
PRINT ""

resultVal = recurseMath(2)

PRINT "EXPECTED RESULT: 31"
PRINT "ACTUAL RESULT  : "; resultVal

IF resultVal = 31 THEN
  PRINT "STATUS: SUCCESS"
ELSE
  PRINT "STATUS: FAILED (Math Corrupted via recursion)"
END IF
WaitEnter

' ----- PAGE 7: FLOATING-POINT UNARY NEGATION -----
CLS
PRINT "[ PAGE 7: FLOATING-POINT UNARY NEGATION ]"
PRINT ""
PRINT "--- DOUBLE PRECISION TEST ---"
startDouble# = 1.5#
negDouble# = -startDouble#

PRINT "EXPECTED : -1.5"
PRINT "ACTUAL   : "; negDouble#
PRINT " "

PRINT "--- SINGLE PRECISION TEST ---"
startSingle! = 1.5!
negSingle! = -startSingle!

PRINT "EXPECTED : -1.5"
PRINT "ACTUAL   : "; negSingle!
PRINT " "

PRINT "Without the fix, the actual values will incorrectly show -1."
PRINT "With the fix, they will correctly show -1.5."
WaitEnter

' ----- PAGE 8: FLOAT-TO-INTEGER COMPILER PARITY TEST -----
CLS
PRINT "[ PAGE 8: FLOAT-TO-INTEGER COMPILER PARITY TEST ]"
PRINT ""

testA% = 1.6
PRINT "TEST 1: Assigning 1.6 to Integer"
PRINT "EXPECTED : 2   |   ACTUAL : "; testA%
PRINT ""

testB% = 1.5
testC% = 2.5
PRINT "TEST 2: Banker's Rounding (1.5 and 2.5)"
PRINT "EXPECTED : 2 and 2   |   ACTUAL : "; testB%; " and "; testC%
PRINT ""

resIDiv = 5.6 \ 2
PRINT "TEST 3: Integer Division (5.6 \ 2)"
PRINT "EXPECTED : 3   |   ACTUAL : "; resIDiv
PRINT ""

resAnd = 5.6 AND 1
PRINT "TEST 4: Bitwise AND (5.6 AND 1)"
PRINT "EXPECTED : 0   |   ACTUAL : "; resAnd
PRINT ""

testD% = -1.6
PRINT "TEST 5: Negative Assignment (-1.6)"
PRINT "EXPECTED :-2   |   ACTUAL : "; testD%
WaitEnter

' ----- PAGE 9: RUNTIME HELPER STACK FRAME & MIXED PRINTING -----
CLS
PRINT "[ PAGE 9: RUNTIME HELPER STACK FRAME & MIXED PRINTING ]"
PRINT ""

' Perform the assignments (Testing RT_STR_ASSIGN)
msg1$ = "Hello"
msg2$ = "World"
msg3$ = msg1$
msg3$ = "Re-entrant String"

valInt1& = 42
valInt2& = -987654

valFlt1! = 3.14159
valFlt2! = -273.15

' Testing RT_PRINT_STR and RT_CRLF
PRINT "--- STRING ASSIGNMENT & PRINTING ---"
PRINT "ACTUAL   : "; msg1$; " | "; msg2$; " | "; msg3$
PRINT "EXPECTED : Hello | World | Re-entrant String"
PRINT ""

' Testing RT_PRINT_INT
PRINT "--- INTEGER PRINTING ---"
PRINT "ACTUAL   : "; valInt1&; " | "; valInt2&
PRINT "EXPECTED : 42 | -987654"
PRINT ""

' Testing RT_PRINT_FLOAT
PRINT "--- FLOAT PRINTING ---"
PRINT "ACTUAL   : "; valFlt1!; " | "; valFlt2!
PRINT "EXPECTED : 3.14159 | -273.15"
PRINT ""

' Ultimate Re-entrancy Test (Hammering the stack frame)
PRINT "--- MIXED STACK / RE-ENTRANCY TEST ---"
PRINT "ACTUAL   : "; msg1$; " | "; valInt1&; " | "; valFlt1!
PRINT "EXPECTED : Hello | 42 | 3.14159"
PRINT ""

PRINT "If ACTUAL matches EXPECTED exactly, the runtimes are flawless!"

PRINT ""
PRINT "Press ENTER to exit..."
DO
  kk$ = INKEY$
LOOP UNTIL kk$ = CHR$(13)

DO
  kk$ = INKEY$
LOOP UNTIL kk$ = ""

END

''''''''''''''''''''''''
FUNCTION recurseMath (nVal)

  IF nVal <= 0 THEN
    tempRet = 1
  ELSE
    ' The left side (nVal * 10) evaluates first and is stored in ~T_0
    ' Then the right side recursively calls itself
    ' If ~T_0 is global, the inner call overwrites the outer call's ~T_0
    tempRet = (nVal * 10) + recurseMath(nVal - 1)
  END IF

  recurseMath = tempRet

END FUNCTION ' recurseMath

''''''''''''''''''''''''
SUB WaitEnter
  PRINT ""
  PRINT "--- Press ENTER for the next page ---"

  DO
    kk$ = INKEY$
  LOOP UNTIL kk$ = CHR$(13)

  DO
    kk$ = INKEY$
  LOOP UNTIL kk$ = ""
END SUB ' WaitEnter

