' Abstract array-of-UDT LONG field test

TYPE fieldProbeRecord
  textBlock AS STRING * 64
  slot01 AS LONG
  slot02 AS LONG
  slot03 AS LONG
  slot04 AS LONG
  slot05 AS LONG
  slot06 AS LONG
  slot07 AS LONG
  slot08 AS LONG
  slot09 AS LONG
  slot10 AS LONG
  slot11 AS LONG
  slot12 AS LONG
END TYPE

DIM SHARED fieldRows(2) AS fieldProbeRecord

COMMON SHARED longValue AS LONG
COMMON SHARED singleValue AS SINGLE
COMMON SHARED scaleSingle AS SINGLE
COMMON SHARED doubleValue AS DOUBLE
COMMON SHARED resultSingle AS SINGLE
COMMON SHARED resultDouble AS DOUBLE
COMMON SHARED observedValue AS LONG
COMMON SHARED failureCount AS LONG

fieldRows(0).slot08 = 8080
fieldRows(0).slot09 = 0
fieldRows(0).slot10 = -1
fieldRows(0).slot11 = 1111

fieldRows(1).slot08 = 8181
fieldRows(1).slot09 = -1
fieldRows(1).slot10 = 0
fieldRows(1).slot11 = 1212

fieldRows(2).slot08 = 8282
fieldRows(2).slot09 = 1
fieldRows(2).slot10 = 2147483647
fieldRows(2).slot11 = 1313

failureCount = 0

rowIndex = 0
readZero = fieldRows(rowIndex).slot09
neighborNegative = fieldRows(rowIndex).slot10

rowIndex = 1
readNegative = fieldRows(rowIndex).slot09
neighborZero = fieldRows(rowIndex).slot10

rowIndex = 2
readPositive = fieldRows(rowIndex).slot09
neighborPositive = fieldRows(rowIndex).slot10

PRINT "ZERO FIELD:       "; readZero
PRINT "NEGATIVE FIELD:   "; readNegative
PRINT "POSITIVE FIELD:   "; readPositive
PRINT "NEIGHBOR -1:      "; neighborNegative
PRINT "NEIGHBOR 0:       "; neighborZero
PRINT "NEIGHBOR MAX LONG:"; neighborPositive

IF readZero <> 0 THEN failureCount = failureCount + 1
IF readNegative <> -1 THEN failureCount = failureCount + 1
IF readPositive <> 1 THEN failureCount = failureCount + 1

IF neighborNegative <> -1 THEN failureCount = failureCount + 1
IF neighborZero <> 0 THEN failureCount = failureCount + 1
IF neighborPositive <> 2147483647 THEN failureCount = failureCount + 1

IF fieldRows(0).slot09 <> 0 THEN failureCount = failureCount + 1
IF fieldRows(1).slot09 <> -1 THEN failureCount = failureCount + 1
IF fieldRows(2).slot09 <> 1 THEN failureCount = failureCount + 1

PRINT "FAILURE COUNT:    "; failureCount

IF failureCount = 0 THEN
  PRINT "PASS"
ELSE
  PRINT "FAIL"
END IF

PRINT
PRINT "Press Space to continue to the next page"
DO
  keyPress$ = INKEY$
  IF keyPress$ = " " THEN EXIT DO
LOOP
CLS

''''''''''''''''''''''''

' Abstract mixed LONG and SINGLE arithmetic test

longValue = 16777217

singleValue = 1!
resultSingle = longValue + singleValue
observedValue = CLNG(resultSingle)
PRINT "LONG + SINGLE:       "; observedValue; " EXPECTED:"; 16777216
IF observedValue <> 16777216 THEN failureCount = failureCount + 1

resultSingle = singleValue + longValue
observedValue = CLNG(resultSingle)
PRINT "SINGLE + LONG:       "; observedValue; " EXPECTED:"; 16777216
IF observedValue <> 16777216 THEN failureCount = failureCount + 1

resultSingle = longValue - singleValue
observedValue = CLNG(resultSingle)
PRINT "LONG - SINGLE:       "; observedValue; " EXPECTED:"; 16777215
IF observedValue <> 16777215 THEN failureCount = failureCount + 1

resultSingle = singleValue - longValue
observedValue = CLNG(resultSingle)
PRINT "SINGLE - LONG:       "; observedValue; " EXPECTED:"; -16777215
IF observedValue <> -16777215 THEN failureCount = failureCount + 1

singleValue = 3!
resultSingle = longValue * singleValue
observedValue = CLNG(resultSingle)
PRINT "LONG * SINGLE:       "; observedValue; " EXPECTED:"; 50331648
IF observedValue <> 50331648 THEN failureCount = failureCount + 1

singleValue = 5!
scaleSingle = 4!
resultSingle = longValue / singleValue
resultSingle = resultSingle * scaleSingle
observedValue = CLNG(resultSingle)
PRINT "LONG / SINGLE * 4:   "; observedValue; " EXPECTED:"; 13421773
IF observedValue <> 13421773 THEN failureCount = failureCount + 1

longValue = 16777216
singleValue = 1!
resultSingle = longValue + singleValue
observedValue = CLNG(resultSingle)
PRINT "EXACT SINGLE CONTROL:"; observedValue; " EXPECTED:"; 16777216
IF observedValue <> 16777216 THEN failureCount = failureCount + 1

longValue = 16777217
doubleValue = 1#
resultDouble = longValue + doubleValue
observedValue = CLNG(resultDouble)
PRINT "DOUBLE CONTROL:      "; observedValue; " EXPECTED:"; 16777218
IF observedValue <> 16777218 THEN failureCount = failureCount + 1

PRINT
PRINT "TOTAL FAILURE COUNT:"; failureCount

IF failureCount = 0 THEN
  PRINT "OVERALL PASS"
ELSE
  PRINT "OVERALL FAIL"
END IF

END

