' TEST BYREF STRUCT UDT
' Tests BYREF Copy-Out, nested UDT assignment integrity,
' whole-array descriptor propagation, numeric UDT field address preservation,
' and computed array-element argument isolation

TYPE ChildStruct
  NestedMessage AS STRING
  NestedValue AS INTEGER
END TYPE

TYPE ParentStruct
  MainMessage AS STRING
  MainValue AS INTEGER
  InnerData AS ChildStruct
END TYPE

TYPE NumericCopyOutStruct
  FirstValue AS INTEGER
  SecondValue AS INTEGER
  GuardValue AS _UNSIGNED _BYTE
END TYPE

DIM SHARED testArray(5) AS STRING
DIM SHARED testStruct AS ParentStruct
DIM SHARED myParent AS ParentStruct

DIM SHARED numericTarget AS NumericCopyOutStruct
DIM SHARED numericScratch AS NumericCopyOutStruct

DIM SHARED testFactorA AS INTEGER
DIM SHARED testFactorB AS INTEGER

' Test 6 data
DIM SHARED expressionSource(7) AS _UNSIGNED _BYTE
DIM SHARED expressionObserved(3) AS LONG
DIM SHARED expressionTableBase AS LONG
DIM SHARED expressionCallIndex AS INTEGER

DIM test5Passed AS INTEGER
DIM test6Passed AS INTEGER

testArray(2) = "Original Array Data"

testStruct.InnerData.NestedMessage = "Original Nested UDT Data"
testStruct.InnerData.NestedValue = 100

myParent.MainMessage = "Original Outer Message"
myParent.InnerData.NestedMessage = "Original Inner Message"

numericTarget.FirstValue = 10
numericTarget.SecondValue = 20
numericTarget.GuardValue = 7

numericScratch.FirstValue = 0
numericScratch.SecondValue = 0
numericScratch.GuardValue = 9

testFactorA = 4
testFactorB = 4

' Test 6 initialization
expressionTableBase = 3
expressionCallIndex = 0

expressionSource(0) = 11
expressionSource(1) = 22
expressionSource(2) = 33
expressionSource(3) = 44
expressionSource(4) = 55
expressionSource(5) = 66
expressionSource(6) = 77
expressionSource(7) = 88

expressionObserved(0) = 0
expressionObserved(1) = 0
expressionObserved(2) = 0
expressionObserved(3) = 0

PRINT "1. Testing Array Element Copy-Out..."
modifyArray testArray(2)
IF testArray(2) = "Modified Array Data Successfully!" THEN
  PRINT "   [SUCCESS] Array element modified correctly"
ELSE
  PRINT "   [FAILURE] Array element was not modified"
  PRINT "   Expected: Modified Array Data Successfully!"
  PRINT "   Actual:   "; testArray(2)
END IF
PRINT ""

PRINT "2. Testing UDT Field Copy-Out..."
modifyUdtField testStruct.InnerData.NestedMessage
IF testStruct.InnerData.NestedMessage = "Modified Nested UDT Data Successfully!" THEN
  PRINT "   [SUCCESS] UDT field modified correctly"
ELSE
  PRINT "   [FAILURE] UDT field was not modified"
  PRINT "   Expected: Modified Nested UDT Data Successfully!"
  PRINT "   Actual:   "; testStruct.InnerData.NestedMessage
END IF
PRINT ""

PRINT "3. Testing Direct UDT Copy-Out..."
modifyDirectUdt testStruct
IF testStruct.InnerData.NestedValue = 999 THEN
  PRINT "   [SUCCESS] Direct UDT parameter modified correctly"
ELSE
  PRINT "   [FAILURE] Direct UDT parameter was BYVAL"
  PRINT "   Expected: 999"
  PRINT "   Actual:   "; testStruct.InnerData.NestedValue
END IF
PRINT ""

PRINT "4. Testing Whole-Array Descriptor Copy-Out..."
REDIM testDynamic(2) AS STRING
testDynamic(1) = "Before REDIM"
modifyWholeArray testDynamic()
IF UBOUND(testDynamic) = 15 THEN
  PRINT "   [SUCCESS] Array descriptor updated correctly"
ELSE
  PRINT "   [FAILURE] Array descriptor unchanged"
  PRINT "   Expected UBound: 15"
  PRINT "   Actual UBound:   "; UBOUND(testDynamic)
END IF
PRINT ""

PRINT "5. Testing Numeric UDT Field Address Preservation..."

modifyNumericUdtFields numericTarget.FirstValue, numericTarget.SecondValue

test5Passed = 1

IF numericTarget.FirstValue <> 111 THEN test5Passed = 0
IF numericTarget.SecondValue <> 222 THEN test5Passed = 0
IF numericTarget.GuardValue <> 7 THEN test5Passed = 0

IF numericScratch.FirstValue <> 16 THEN test5Passed = 0
IF numericScratch.SecondValue <> 32 THEN test5Passed = 0
IF numericScratch.GuardValue <> 9 THEN test5Passed = 0

IF test5Passed = 1 THEN
  PRINT "   [SUCCESS] Numeric UDT field addresses survived the SUB call"
ELSE
  PRINT "   [FAILURE] Numeric UDT field address staging was corrupted"

  PRINT "   Expected target FirstValue:  111"
  PRINT "   Actual target FirstValue:   "; numericTarget.FirstValue

  PRINT "   Expected target SecondValue: 222"
  PRINT "   Actual target SecondValue:  "; numericTarget.SecondValue

  PRINT "   Expected target GuardValue:  7"
  PRINT "   Actual target GuardValue:   "; numericTarget.GuardValue

  PRINT "   Expected scratch FirstValue: 16"
  PRINT "   Actual scratch FirstValue:  "; numericScratch.FirstValue

  PRINT "   Expected scratch SecondValue: 32"
  PRINT "   Actual scratch SecondValue: "; numericScratch.SecondValue

  PRINT "   Expected scratch GuardValue: 9"
  PRINT "   Actual scratch GuardValue:  "; numericScratch.GuardValue
END IF
PRINT ""

PRINT "6. Testing Computed Array-Element Argument Isolation..."

' These four calls reproduce the important structure used by the tile code:
'
'   scalar arithmetic + array(computed index)
'
' The argument is a computed value, not a writable array element.
' The SUB does not modify the argument.
'
' A broken compiler may retain the array element address after completing
' the addition and incorrectly copy the argument value back into the array.

captureComputedArrayValue (expressionTableBase * 256) + expressionSource(0)
captureComputedArrayValue (expressionTableBase * 256) + expressionSource(1)
captureComputedArrayValue (expressionTableBase * 256) + expressionSource(2)
captureComputedArrayValue (expressionTableBase * 256) + expressionSource(3)

test6Passed = 1

' Verify that each call received a different and correct computed value
IF expressionObserved(0) <> 779 THEN test6Passed = 0
IF expressionObserved(1) <> 790 THEN test6Passed = 0
IF expressionObserved(2) <> 801 THEN test6Passed = 0
IF expressionObserved(3) <> 812 THEN test6Passed = 0

' Verify that the source array was not modified by erroneous copy-out
IF expressionSource(0) <> 11 THEN test6Passed = 0
IF expressionSource(1) <> 22 THEN test6Passed = 0
IF expressionSource(2) <> 33 THEN test6Passed = 0
IF expressionSource(3) <> 44 THEN test6Passed = 0
IF expressionSource(4) <> 55 THEN test6Passed = 0
IF expressionSource(5) <> 66 THEN test6Passed = 0
IF expressionSource(6) <> 77 THEN test6Passed = 0
IF expressionSource(7) <> 88 THEN test6Passed = 0

IF expressionTableBase <> 3 THEN test6Passed = 0
IF expressionCallIndex <> 4 THEN test6Passed = 0

IF test6Passed = 1 THEN
  PRINT "   [SUCCESS] Computed array arguments remained isolated"
ELSE
  PRINT "   [FAILURE] Computed argument metadata corrupted the source array"

  PRINT "   Expected observed value 0: 779"
  PRINT "   Actual observed value 0:  "; expressionObserved(0)

  PRINT "   Expected observed value 1: 790"
  PRINT "   Actual observed value 1:  "; expressionObserved(1)

  PRINT "   Expected observed value 2: 801"
  PRINT "   Actual observed value 2:  "; expressionObserved(2)

  PRINT "   Expected observed value 3: 812"
  PRINT "   Actual observed value 3:  "; expressionObserved(3)

  PRINT ""
  PRINT "   Expected source values:"
  PRINT "   11 22 33 44 55 66 77 88"

  PRINT "   Actual source values:"
  PRINT "  "; expressionSource(0);
  PRINT " "; expressionSource(1);
  PRINT " "; expressionSource(2);
  PRINT " "; expressionSource(3);
  PRINT " "; expressionSource(4);
  PRINT " "; expressionSource(5);
  PRINT " "; expressionSource(6);
  PRINT " "; expressionSource(7)

  PRINT ""
  PRINT "   Expected table base: 3"
  PRINT "   Actual table base:  "; expressionTableBase

  PRINT "   Expected call count: 4"
  PRINT "   Actual call count:  "; expressionCallIndex
END IF
PRINT ""


PRINT "7. Testing Nested UDT Assignment Independence..."
DIM cloneParent AS ParentStruct
cloneParent = myParent
cloneParent.InnerData.NestedMessage = "CORRUPTING SHALLOW COPY!"
IF myParent.InnerData.NestedMessage = "Original Inner Message" THEN
  PRINT "   [SUCCESS] Original value remained intact"
ELSE
  PRINT "   [FAILURE] Nested string storage was shared"
  PRINT "   Expected: Original Inner Message"
  PRINT "   Actual:   "; myParent.InnerData.NestedMessage
END IF
PRINT ""


PRINT "End of tests."

END

SUB modifyArray (element AS STRING) ' Used in test 1
  ' If Copy-Out fails, this change will be discarded
  element = "Modified Array Data Successfully!"
END SUB ' modifyArray

SUB modifyUdtField (targetStr AS STRING) ' Used in test 2
  ' If Copy-Out fails, this change will be discarded
  targetStr = "Modified Nested UDT Data Successfully!"
END SUB ' modifyUdtField

SUB modifyDirectUdt (struct AS ParentStruct) ' Used in test 3
  ' If Direct UDTs are trapped as BYVAL, this change will be discarded
  struct.InnerData.NestedValue = 999
END SUB ' modifyDirectUdt

SUB modifyWholeArray (arr() AS STRING) ' Used in test 4
  ' If the array descriptor is not copied back, the caller may retain the old array
  REDIM arr(15) AS STRING
  arr(1) = "After REDIM"
END SUB ' modifyWholeArray

SUB modifyNumericUdtFields (firstValue AS INTEGER, secondValue AS INTEGER) ' Used in test 5
  ' These expressions deliberately allocate and reuse several TIRA temporaries
  ' A broken compiler may replace the saved caller field addresses with these values or addresses

  numericScratch.FirstValue = testFactorA * testFactorB
  numericScratch.SecondValue = testFactorA * (testFactorB + testFactorA)
  numericScratch.GuardValue = 9

  ' These values must be copied back to numericTarget.FirstValue and numericTarget.SecondValue
  firstValue = 111
  secondValue = 222
END SUB ' modifyNumericUdtFields

SUB captureComputedArrayValue (value AS LONG) ' Used in test 6
  ' This SUB deliberately does not modify value.
  '
  ' The caller passed a computed expression, so there must not be any
  ' copy-out into expressionSource() after this SUB returns.

  expressionObserved(expressionCallIndex) = value
  expressionCallIndex = expressionCallIndex + 1
END SUB ' captureComputedArrayValue

