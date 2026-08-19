' Rigorous branching evaluation suite, designed for ELSEIF testing

DIM SHARED testsPassed AS LONG
DIM SHARED testsFailed AS LONG

testsPassed = 0
testsFailed = 0

PRINT "Starting rigorous test suite"
PRINT ""

' Test 1 Basic True evaluation
PRINT "Test 1: Target hits first condition"
testVal = 1

IF testVal = 1 THEN
  testsPassed = testsPassed + 1
ELSEIF testVal = 2 THEN
  testsFailed = testsFailed + 1
ELSE
  testsFailed = testsFailed + 1
END IF

' Test 2 Basic False falling to next condition
PRINT "Test 2: Target hits second condition"
testVal = 2

IF testVal = 1 THEN
  testsFailed = testsFailed + 1
ELSEIF testVal = 2 THEN
  testsPassed = testsPassed + 1
ELSE
  testsFailed = testsFailed + 1
END IF

' Test 3 Deep chain catching the middle
PRINT "Test 3: Target hits middle of deep chain"
testVal = 3

IF testVal = 1 THEN
  testsFailed = testsFailed + 1
ELSEIF testVal = 2 THEN
  testsFailed = testsFailed + 1
ELSEIF testVal = 3 THEN
  testsPassed = testsPassed + 1
ELSEIF testVal = 4 THEN
  testsFailed = testsFailed + 1
ELSE
  testsFailed = testsFailed + 1
END IF

' Test 4 Deep chain falling to fallback block
PRINT "Test 4: Target misses all and hits fallback"
testVal = 5

IF testVal = 1 THEN
  testsFailed = testsFailed + 1
ELSEIF testVal = 2 THEN
  testsFailed = testsFailed + 1
ELSEIF testVal = 3 THEN
  testsFailed = testsFailed + 1
ELSE
  testsPassed = testsPassed + 1
END IF

' Test 5 Early exit in deep chain
PRINT "Test 5: Target hits first match and skips remainder"
testVal = 2

IF testVal = 1 THEN
  testsFailed = testsFailed + 1
ELSEIF testVal = 2 THEN
  testsPassed = testsPassed + 1
ELSEIF testVal = 2 THEN
  testsFailed = testsFailed + 1
ELSE
  testsFailed = testsFailed + 1
END IF

' Test 6 Nested branching isolation
PRINT "Test 6: Target evaluates nested block safely"
testVal = 10
testSub = 20

IF testVal = 1 THEN
  testsFailed = testsFailed + 1
ELSEIF testVal = 10 THEN
  IF testSub = 20 THEN
    testsPassed = testsPassed + 1
  ELSE
    testsFailed = testsFailed + 1
  END IF
ELSE
  testsFailed = testsFailed + 1
END IF

' Test 7 String evaluations
PRINT "Test 7: Target handles string comparisons"
testStr$ = "EMERALD"

IF testStr$ = "CLASSIC" THEN
  testsFailed = testsFailed + 1
ELSEIF testStr$ = "EMERALD" THEN
  testsPassed = testsPassed + 1
ELSE
  testsFailed = testsFailed + 1
END IF

PRINT ""
PRINT "Total Tests Passed: "; testsPassed
PRINT "Total Tests Failed: "; testsFailed

IF testsFailed = 0 THEN
  PRINT "Logic blocks evaluated successfully"
ELSE
  PRINT "Logic failures detected"
END IF

