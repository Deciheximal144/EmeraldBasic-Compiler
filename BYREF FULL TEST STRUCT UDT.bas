' TEST BYREF STRUCT UDT
' Tests BYREF Copy-Out, nested UDT assignment integrity,
' whole-array descriptor propagation, numeric UDT field address preservation,
' computed array-element argument isolation, argument staging beyond four parameters,
' alias preservation, dynamic string return lifetime, nonzero array lower bounds,
' UDT array-element copy-out, fixed-length string behavior, early-exit cleanup,
' self-referential string assignment, SELECT CASE control flow,
' local dynamic-array cleanup, function copy-out, function array descriptors,
' recursive call-frame isolation, nested function heap preservation,
' string typing, string argument temporaries, MID$ boundaries,
' lexer-style string parsing, empty array strings, string reallocation,
' CHR$/ASC identity, function copy-out collision protection,
' UDT array string reassignment, and writable two-argument ASC behavior

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

TYPE FixedStringStruct
  Code AS STRING * 8
  Value AS INTEGER
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

' Test 11 data
DIM SHARED boundedMatrix(2 TO 4, 5 TO 7) AS LONG

' Test 12 and Test 30 data
DIM SHARED parentArray(2) AS ParentStruct

' Test 18 data
DIM SHARED functionCopyArray(4) AS INTEGER

DIM test5Passed AS INTEGER
DIM test6Passed AS INTEGER
DIM test8Passed AS INTEGER
DIM test9Passed AS INTEGER
DIM test10Passed AS INTEGER
DIM test11Passed AS INTEGER
DIM test12Passed AS INTEGER
DIM test13Passed AS INTEGER
DIM test14Passed AS INTEGER
DIM test15Passed AS INTEGER
DIM test16Passed AS INTEGER
DIM test17Passed AS INTEGER
DIM test18Passed AS INTEGER
DIM test19Passed AS INTEGER
DIM test20Passed AS INTEGER
DIM test21Passed AS INTEGER
DIM test22Passed AS INTEGER
DIM test23Passed AS INTEGER
DIM test24Passed AS INTEGER
DIM test25Passed AS INTEGER
DIM test26Passed AS INTEGER
DIM test27Passed AS INTEGER
DIM test28Passed AS INTEGER
DIM test29Passed AS INTEGER
DIM test30Passed AS INTEGER
DIM test31Passed AS INTEGER

DIM test8Arg1 AS INTEGER
DIM test8Arg2 AS LONG
DIM test8Arg4 AS INTEGER
DIM test8Arg6 AS LONG
DIM test8Arg7 AS INTEGER

DIM test9Numeric AS INTEGER

DIM test13Scalar AS STRING * 8
DIM test13Record AS FixedStringStruct
DIM test13Copy AS FixedStringStruct

DIM test16Numeric AS INTEGER

DIM test17FailureAt AS INTEGER

DIM test18Scalar AS INTEGER

DIM test21FailureAt AS LONG
DIM test21Index AS LONG
DIM test21Actual AS STRING
DIM test21Expected AS STRING
DIM test21FailureActual AS STRING
DIM test21FailureExpected AS STRING

DIM test22Target AS STRING
DIM test22Result AS STRING

DIM test23Result AS STRING

DIM test24Source AS STRING
DIM test24Empty AS STRING
DIM test24Partial AS STRING

DIM test25Code AS STRING
DIM test25Command AS STRING
DIM test25Argument AS STRING
DIM test25SpacePos AS LONG

DIM test26Combine AS STRING

DIM test27Long AS STRING
DIM test27Iteration AS INTEGER

DIM test28Character AS STRING
DIM test28Value AS INTEGER
DIM test28FailureAt AS INTEGER
DIM test28FailureValue AS INTEGER
DIM test28Index AS INTEGER

DIM test29Variable AS STRING
DIM test29Return AS STRING

DIM test31Text AS STRING
DIM test31Value AS INTEGER

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

CLS

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

pauseForNextPage

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

PRINT "8. Testing Eight-Argument Mixed-Type Staging..."

test8Arg1 = 1
test8Arg2 = 2
test8Arg3$ = "Three"
test8Arg4 = 4
test8Arg5$ = "Five"
test8Arg6 = 6
test8Arg7 = 7
test8Arg8$ = "Eight"

modifyEightArguments test8Arg1, test8Arg2, test8Arg3$, test8Arg4, test8Arg5$, test8Arg6, test8Arg7, test8Arg8$

test8Passed = 1

IF test8Arg1 <> 11 THEN test8Passed = 0
IF test8Arg2 <> 22 THEN test8Passed = 0
IF test8Arg3$ <> "Three Modified" THEN test8Passed = 0
IF test8Arg4 <> 44 THEN test8Passed = 0
IF test8Arg5$ <> "Five Modified" THEN test8Passed = 0
IF test8Arg6 <> 66 THEN test8Passed = 0
IF test8Arg7 <> 77 THEN test8Passed = 0
IF test8Arg8$ <> "Eight Modified" THEN test8Passed = 0

IF test8Passed = 1 THEN
  PRINT "   [SUCCESS] All eight staged arguments copied in and out correctly"
ELSE
  PRINT "   [FAILURE] One or more argument staging slots were corrupted"
  PRINT "   Expected: 11, 22, Three Modified, 44, Five Modified, 66, 77, Eight Modified"
  PRINT "   Actual:  "; test8Arg1; ", "; test8Arg2; ", "; test8Arg3$; ", "; test8Arg4; ", "; test8Arg5$; ", "; test8Arg6; ", "; test8Arg7; ", "; test8Arg8$
END IF

PRINT ""

pauseForNextPage

PRINT "9. Testing Same-Variable BYREF Aliasing..."

test9Numeric = 10
test9String$ = "X"

modifyAliasedNumeric test9Numeric, test9Numeric
modifyAliasedString test9String$, test9String$

test9Passed = 1

IF test9Numeric <> 26 THEN test9Passed = 0
IF test9String$ <> "XAB" THEN test9Passed = 0

IF test9Passed = 1 THEN
  PRINT "   [SUCCESS] Aliased parameters remained true references"
ELSE
  PRINT "   [FAILURE] Copy-in or copy-out destroyed BYREF alias semantics"
  PRINT "   Expected numeric alias: 26"
  PRINT "   Actual numeric alias:  "; test9Numeric
  PRINT "   Expected string alias: XAB"
  PRINT "   Actual string alias:  "; test9String$
END IF

PRINT ""

PRINT "10. Testing Nested Dynamic-String Function Returns..."

test10First$ = buildStringResult$("ALPHA", 1)
test10Second$ = buildStringResult$("BETA", 2)
test10Nested$ = combineStringResults$(buildStringResult$("LEFT", 3), buildStringResult$("RIGHT", 4))

test10Passed = 1

IF test10First$ <> "<ALPHA:1>" THEN test10Passed = 0
IF test10Second$ <> "<BETA:2>" THEN test10Passed = 0
IF test10Nested$ <> "<LEFT:3>|<RIGHT:4>" THEN test10Passed = 0

IF test10Passed = 1 THEN
  PRINT "   [SUCCESS] Nested string return descriptors remained valid"
ELSE
  PRINT "   [FAILURE] A returned string was overwritten or freed too early"
  PRINT "   Expected first:  <ALPHA:1>"
  PRINT "   Actual first:   "; test10First$
  PRINT "   Expected second: <BETA:2>"
  PRINT "   Actual second:  "; test10Second$
  PRINT "   Expected nested: <LEFT:3>|<RIGHT:4>"
  PRINT "   Actual nested:  "; test10Nested$
END IF

PRINT ""

PRINT "11. Testing Nonzero Lower Bounds and Two-Dimensional Descriptors..."

boundedMatrix(2, 5) = 25
boundedMatrix(4, 7) = 47
boundedMatrix(3, 6) = 0

modifyBoundedMatrix boundedMatrix()

test11Passed = 1

IF LBOUND(boundedMatrix, 1) <> 2 THEN test11Passed = 0
IF UBOUND(boundedMatrix, 1) <> 4 THEN test11Passed = 0
IF LBOUND(boundedMatrix, 2) <> 5 THEN test11Passed = 0
IF UBOUND(boundedMatrix, 2) <> 7 THEN test11Passed = 0

IF boundedMatrix(2, 5) <> 125 THEN test11Passed = 0
IF boundedMatrix(4, 7) <> 447 THEN test11Passed = 0
IF boundedMatrix(3, 6) <> 572 THEN test11Passed = 0

IF test11Passed = 1 THEN
  PRINT "   [SUCCESS] Lower bounds and multidimensional indexing were preserved"
ELSE
  PRINT "   [FAILURE] Array descriptor bounds or multidimensional addressing were wrong"
  PRINT "   Expected dimension 1: 2 TO 4"
  PRINT "   Actual dimension 1:  "; LBOUND(boundedMatrix, 1); " TO "; UBOUND(boundedMatrix, 1)
  PRINT "   Expected dimension 2: 5 TO 7"
  PRINT "   Actual dimension 2:  "; LBOUND(boundedMatrix, 2); " TO "; UBOUND(boundedMatrix, 2)
  PRINT "   Expected values: 125, 572, 447"
  PRINT "   Actual values:  "; boundedMatrix(2, 5); ", "; boundedMatrix(3, 6); ", "; boundedMatrix(4, 7)
END IF

PRINT ""

PRINT "12. Testing UDT Array-Element Deep Copy and Copy-Out..."

parentArray(0).MainMessage = "Original Array Parent"
parentArray(0).MainValue = 10
parentArray(0).InnerData.NestedMessage = "Original Array Child"
parentArray(0).InnerData.NestedValue = 20

parentArray(2).MainMessage = "Guard Parent"
parentArray(2).InnerData.NestedMessage = "Guard Child"

parentArray(1) = parentArray(0)

modifyUdtArrayElement parentArray(1)

test12Passed = 1

IF parentArray(0).MainMessage <> "Original Array Parent" THEN test12Passed = 0
IF parentArray(0).MainValue <> 10 THEN test12Passed = 0
IF parentArray(0).InnerData.NestedMessage <> "Original Array Child" THEN test12Passed = 0
IF parentArray(0).InnerData.NestedValue <> 20 THEN test12Passed = 0

IF parentArray(1).MainMessage <> "Modified Array Parent" THEN test12Passed = 0
IF parentArray(1).MainValue <> 111 THEN test12Passed = 0
IF parentArray(1).InnerData.NestedMessage <> "Modified Array Child" THEN test12Passed = 0
IF parentArray(1).InnerData.NestedValue <> 222 THEN test12Passed = 0

IF parentArray(2).MainMessage <> "Guard Parent" THEN test12Passed = 0
IF parentArray(2).InnerData.NestedMessage <> "Guard Child" THEN test12Passed = 0

IF test12Passed = 1 THEN
  PRINT "   [SUCCESS] UDT array elements copied deeply and copied out correctly"
ELSE
  PRINT "   [FAILURE] UDT array-element addressing or dynamic-string ownership was corrupted"
  PRINT "   Element 0 parent: "; parentArray(0).MainMessage
  PRINT "   Element 0 child:  "; parentArray(0).InnerData.NestedMessage
  PRINT "   Element 1 parent: "; parentArray(1).MainMessage
  PRINT "   Element 1 child:  "; parentArray(1).InnerData.NestedMessage
  PRINT "   Element 2 parent: "; parentArray(2).MainMessage
  PRINT "   Element 2 child:  "; parentArray(2).InnerData.NestedMessage
END IF

PRINT ""

pauseForNextPage

PRINT "13. Testing Fixed-Length String Storage and UDT Copying..."

test13Scalar = "ABCDEFGHIJK"

test13Record.Code = "XY"
test13Record.Value = 77

test13Copy = test13Record
test13Copy.Code = "123456789"
test13Copy.Value = 88

test13Passed = 1

IF LEN(test13Scalar) <> 8 THEN test13Passed = 0
IF test13Scalar <> "ABCDEFGH" THEN test13Passed = 0

IF LEN(test13Record.Code) <> 8 THEN test13Passed = 0
IF test13Record.Code <> "XY      " THEN test13Passed = 0
IF test13Record.Value <> 77 THEN test13Passed = 0

IF LEN(test13Copy.Code) <> 8 THEN test13Passed = 0
IF test13Copy.Code <> "12345678" THEN test13Passed = 0
IF test13Copy.Value <> 88 THEN test13Passed = 0

IF test13Passed = 1 THEN
  PRINT "   [SUCCESS] Fixed strings padded, truncated, and copied correctly"
ELSE
  PRINT "   [FAILURE] Fixed-length string storage or UDT byte copying was wrong"
  PRINT "   Expected scalar: [ABCDEFGH]"
  PRINT "   Actual scalar:   ["; test13Scalar; "]"
  PRINT "   Expected record: [XY      ] value 77"
  PRINT "   Actual record:   ["; test13Record.Code; "] value "; test13Record.Value
  PRINT "   Expected copy:   [12345678] value 88"
  PRINT "   Actual copy:     ["; test13Copy.Code; "] value "; test13Copy.Value
END IF

PRINT ""

PRINT "14. Testing EXIT SUB and EXIT FUNCTION Cleanup..."

test14Text$ = "Original"

earlyCopyOut test14Text$, 1

test14Early$ = earlyStringResult$(1)
test14Late$ = earlyStringResult$(0)
test14EarlyAgain$ = earlyStringResult$(1)

test14Passed = 1

IF test14Text$ <> "Early Exit Copy-Out" THEN test14Passed = 0
IF test14Early$ <> "Early Return" THEN test14Passed = 0
IF test14Late$ <> "Late Return" THEN test14Passed = 0
IF test14EarlyAgain$ <> "Early Return" THEN test14Passed = 0

IF test14Passed = 1 THEN
  PRINT "   [SUCCESS] Early exits preserved copy-out and string cleanup"
ELSE
  PRINT "   [FAILURE] Early-exit labels bypassed copy-out or corrupted return storage"
  PRINT "   Expected SUB value: Early Exit Copy-Out"
  PRINT "   Actual SUB value:  "; test14Text$
  PRINT "   Expected first function value: Early Return"
  PRINT "   Actual first function value:  "; test14Early$
  PRINT "   Expected late function value: Late Return"
  PRINT "   Actual late function value:  "; test14Late$
  PRINT "   Expected repeated value: Early Return"
  PRINT "   Actual repeated value:  "; test14EarlyAgain$
END IF

PRINT ""

PRINT "15. Testing Self-Referential Dynamic-String Assignment..."

test15Text$ = "AB"
test15Text$ = test15Text$ + "-" + test15Text$

testArray(2) = "ARRAY"
testArray(2) = testArray(2) + "|" + testArray(2)

testStruct.InnerData.NestedMessage = "UDT"
testStruct.InnerData.NestedMessage = testStruct.InnerData.NestedMessage + ":" + testStruct.InnerData.NestedMessage

test15Passed = 1

IF test15Text$ <> "AB-AB" THEN test15Passed = 0
IF testArray(2) <> "ARRAY|ARRAY" THEN test15Passed = 0
IF testStruct.InnerData.NestedMessage <> "UDT:UDT" THEN test15Passed = 0

IF test15Passed = 1 THEN
  PRINT "   [SUCCESS] String destinations did not invalidate their own sources"
ELSE
  PRINT "   [FAILURE] Self-assignment freed or overwrote a source descriptor"
  PRINT "   Expected scalar: AB-AB"
  PRINT "   Actual scalar:  "; test15Text$
  PRINT "   Expected array: ARRAY|ARRAY"
  PRINT "   Actual array:  "; testArray(2)
  PRINT "   Expected UDT: UDT:UDT"
  PRINT "   Actual UDT:  "; testStruct.InnerData.NestedMessage
END IF

PRINT ""

PRINT "16. Testing SELECT CASE Ranges, Lists, Relations, and Strings..."

test16Passed = 1

test16Numeric = 6
test16RangeResult$ = ""

SELECT CASE test16Numeric
  CASE 1, 2, 3
    test16RangeResult$ = "LOW"

  CASE 4 TO 7
    test16RangeResult$ = "RANGE"

  CASE IS > 7
    test16RangeResult$ = "HIGH"

  CASE ELSE
    test16RangeResult$ = "ELSE"
END SELECT

test16Numeric = 9
test16RelationResult$ = ""

SELECT CASE test16Numeric
  CASE 1, 2, 3
    test16RelationResult$ = "LOW"

  CASE 4 TO 7
    test16RelationResult$ = "RANGE"

  CASE IS > 7
    test16RelationResult$ = "HIGH"

  CASE ELSE
    test16RelationResult$ = "ELSE"
END SELECT

test16SelectText$ = "BETA"
test16StringResult$ = ""

SELECT CASE test16SelectText$
  CASE "ALPHA", "BETA"
    test16StringResult$ = "STRING MATCH"

  CASE "GAMMA"
    test16StringResult$ = "WRONG STRING"

  CASE ELSE
    test16StringResult$ = "STRING ELSE"
END SELECT

IF test16RangeResult$ <> "RANGE" THEN test16Passed = 0
IF test16RelationResult$ <> "HIGH" THEN test16Passed = 0
IF test16StringResult$ <> "STRING MATCH" THEN test16Passed = 0

IF test16Passed = 1 THEN
  PRINT "   [SUCCESS] SELECT CASE control flow matched QB64 behavior"
ELSE
  PRINT "   [FAILURE] SELECT CASE labels or comparisons were corrupted"
  PRINT "   Expected range result: RANGE"
  PRINT "   Actual range result:  "; test16RangeResult$
  PRINT "   Expected relation result: HIGH"
  PRINT "   Actual relation result:  "; test16RelationResult$
  PRINT "   Expected string result: STRING MATCH"
  PRINT "   Actual string result:  "; test16StringResult$
END IF

PRINT ""

pauseForNextPage

PRINT "17. Testing Repeated Local Dynamic String Arrays..."

test17Passed = 1
test17FailureAt = 0
test17FailureActual$ = ""
test17FailureExpected$ = ""

FOR ix = 1 TO 250
  test17Actual$ = localArrayProbe$(ix)
  test17Expected$ = "A" + LTRIM$(STR$(ix)) + "|B" + LTRIM$(STR$(ix + 1)) + "|C" + LTRIM$(STR$(ix + 2))

  IF test17Actual$ <> test17Expected$ THEN
    test17Passed = 0

    IF test17FailureAt = 0 THEN
      test17FailureAt = ix
      test17FailureActual$ = test17Actual$
      test17FailureExpected$ = test17Expected$
    END IF
  END IF
NEXT

IF test17Passed = 1 THEN
  PRINT "   [SUCCESS] Local dynamic arrays survived repeated allocation and cleanup"
ELSE
  PRINT "   [FAILURE] Local array descriptors or string cleanup leaked across calls"
  PRINT "   First failing iteration: "; test17FailureAt
  PRINT "   Expected: "; test17FailureExpected$
  PRINT "   Actual:   "; test17FailureActual$
END IF

PRINT ""

PRINT "18. Testing FUNCTION Copy-Out to Scalars, UDT Fields, and Array Elements..."

test18Scalar = 7
testStruct.InnerData.NestedValue = 30
functionCopyArray(2) = 40

test18ScalarResult = incrementAndReturn(test18Scalar) + 1
test18FieldResult = incrementAndReturn(testStruct.InnerData.NestedValue) + 1
test18ArrayResult = incrementAndReturn(functionCopyArray(2)) + 1

test18Passed = 1

IF test18Scalar <> 12 THEN test18Passed = 0
IF test18ScalarResult <> 121 THEN test18Passed = 0

IF testStruct.InnerData.NestedValue <> 35 THEN test18Passed = 0
IF test18FieldResult <> 351 THEN test18Passed = 0

IF functionCopyArray(2) <> 45 THEN test18Passed = 0
IF test18ArrayResult <> 451 THEN test18Passed = 0

IF test18Passed = 1 THEN
  PRINT "   [SUCCESS] Function arguments copied out to every writable target form"
ELSE
  PRINT "   [FAILURE] Function-expression copy-out lost a complex target address"
  PRINT "   Expected scalar value/result: 12 / 121"
  PRINT "   Actual scalar value/result:  "; test18Scalar; " / "; test18ScalarResult
  PRINT "   Expected UDT value/result: 35 / 351"
  PRINT "   Actual UDT value/result:  "; testStruct.InnerData.NestedValue; " / "; test18FieldResult
  PRINT "   Expected array value/result: 45 / 451"
  PRINT "   Actual array value/result:  "; functionCopyArray(2); " / "; test18ArrayResult
END IF

PRINT ""

PRINT "19. Testing Whole-Array Descriptor Copy-Out from a FUNCTION..."

REDIM functionResizeArray(1) AS STRING

functionResizeArray(0) = "Before Function REDIM"

test19Return = resizeArrayAndReturn(functionResizeArray())

test19Passed = 1

IF test19Return <> 9 THEN test19Passed = 0
IF UBOUND(functionResizeArray) <> 9 THEN test19Passed = 0

IF UBOUND(functionResizeArray) = 9 THEN
  IF functionResizeArray(9) <> "Function Resize" THEN test19Passed = 0
END IF

IF test19Passed = 1 THEN
  PRINT "   [SUCCESS] Function array descriptor changes reached the caller"
ELSE
  PRINT "   [FAILURE] Function array descriptor copy-out was missing or stale"
  PRINT "   Expected function return: 9"
  PRINT "   Actual function return:  "; test19Return
  PRINT "   Expected caller UBound: 9"
  PRINT "   Actual caller UBound:  "; UBOUND(functionResizeArray)

  IF UBOUND(functionResizeArray) = 9 THEN
    PRINT "   Expected element 9: Function Resize"
    PRINT "   Actual element 9:  "; functionResizeArray(9)
  END IF
END IF

PRINT ""

PRINT "20. Testing Recursive String Call Frames..."

test20First$ = buildRecursiveString$(5)
test20Second$ = buildRecursiveString$(3)

test20Passed = 1

IF test20First$ <> "EDCBA" THEN test20Passed = 0
IF test20Second$ <> "CBA" THEN test20Passed = 0

IF test20Passed = 1 THEN
  PRINT "   [SUCCESS] Recursive frames preserved parameters, locals, and returned strings"
ELSE
  PRINT "   [FAILURE] Recursive staging or temporary-heap state was shared between frames"
  PRINT "   Expected first: EDCBA"
  PRINT "   Actual first:  "; test20First$
  PRINT "   Expected second: CBA"
  PRINT "   Actual second:  "; test20Second$
END IF

PRINT ""

pauseForNextPage

PRINT "21. Testing Call Frame Heap Preservation..."

test21Passed = 1
test21FailureAt = 0
test21FailureActual = ""
test21FailureExpected = ""

FOR test21Index = 1 TO 25000
  test21Actual = layerOne$(test21Index)
  test21Expected = "CBA"

  IF test21Actual <> test21Expected THEN
    test21Passed = 0

    IF test21FailureAt = 0 THEN
      test21FailureAt = test21Index
      test21FailureActual = test21Actual
      test21FailureExpected = test21Expected
    END IF
  END IF
NEXT

IF test21Passed = 1 THEN
  PRINT "   [SUCCESS] Temp heap survived massive nested function chains"
ELSE
  PRINT "   [FAILURE] Nested string returns were corrupted"
  PRINT "   First failing iteration: "; test21FailureAt
  PRINT "   Expected: "; test21FailureExpected
  PRINT "   Actual:   "; test21FailureActual
END IF

PRINT ""

PRINT "22. Testing Explicit String Typing..."

test22Passed = 1

test22Target = "Explicitly Typed"
test22Result = UCASE$(test22Target)

IF test22Target <> "Explicitly Typed" THEN test22Passed = 0
IF test22Result <> "EXPLICITLY TYPED" THEN test22Passed = 0

IF test22Passed = 1 THEN
  PRINT "   [SUCCESS] Explicit AS STRING variables retained the correct type and value"
ELSE
  PRINT "   [FAILURE] Explicit AS STRING typing failed"
  PRINT "   Expected source: Explicitly Typed"
  PRINT "   Actual source:   "; test22Target
  PRINT "   Expected result: EXPLICITLY TYPED"
  PRINT "   Actual result:   "; test22Result
END IF

PRINT ""

PRINT "23. Testing Complex Concatenation in Arguments..."

test23Passed = 1

test23Result = buildStringResult$("Left" + "-" + "Right", 99)

IF test23Result <> "<Left-Right:99>" THEN test23Passed = 0

IF test23Passed = 1 THEN
  PRINT "   [SUCCESS] In-argument concatenation processed correctly"
ELSE
  PRINT "   [FAILURE] In-argument concatenation failed"
  PRINT "   Expected: <Left-Right:99>"
  PRINT "   Actual:   "; test23Result
END IF

PRINT ""

PRINT "24. Testing MID$ Out of Bounds Handling..."

test24Passed = 1

test24Source = "Short"
test24Empty = MID$(test24Source, 10, 5)
test24Partial = MID$(test24Source, 4, 10)

IF test24Source <> "Short" THEN test24Passed = 0
IF test24Empty <> "" THEN test24Passed = 0
IF test24Partial <> "rt" THEN test24Passed = 0

IF test24Passed = 1 THEN
  PRINT "   [SUCCESS] MID$ safely clamped out-of-bounds requests"
ELSE
  PRINT "   [FAILURE] MID$ returned incorrect data"
  PRINT "   Expected empty:   []"
  PRINT "   Actual empty:     ["; test24Empty; "]"
  PRINT "   Expected partial: [rt]"
  PRINT "   Actual partial:   ["; test24Partial; "]"
END IF

PRINT ""

pauseForNextPage

PRINT "25. Testing Simulated Compiler Lexer..."

test25Passed = 1

test25Code = "PRINT " + CHR$(34) + "HELLO" + CHR$(34)
test25Command = ""
test25Argument = ""

test25SpacePos = INSTR(test25Code, " ")

IF test25SpacePos > 0 THEN
  test25Command = LEFT$(test25Code, test25SpacePos - 1)
  test25Argument = MID$(test25Code, test25SpacePos + 1, 100)
END IF

IF test25SpacePos <> 6 THEN test25Passed = 0
IF test25Command <> "PRINT" THEN test25Passed = 0
IF test25Argument <> CHR$(34) + "HELLO" + CHR$(34) THEN test25Passed = 0

IF test25Passed = 1 THEN
  PRINT "   [SUCCESS] Simulated lexer successfully extracted tokens"
ELSE
  PRINT "   [FAILURE] Simulated lexer failed"
  PRINT "   Expected command: PRINT"
  PRINT "   Actual command:   "; test25Command
  PRINT "   Expected argument: "; CHR$(34); "HELLO"; CHR$(34)
  PRINT "   Actual argument:   "; test25Argument
END IF

PRINT ""

PRINT "26. Testing Empty Strings in Arrays..."

test26Passed = 1

REDIM test26Array(3) AS STRING

test26Array(0) = ""
test26Array(1) = "Filled"
test26Array(2) = ""
test26Array(3) = "End"

test26Combine = test26Array(0) + test26Array(1) + test26Array(2) + test26Array(3)

IF UBOUND(test26Array) <> 3 THEN test26Passed = 0
IF test26Array(0) <> "" THEN test26Passed = 0
IF test26Array(2) <> "" THEN test26Passed = 0
IF test26Combine <> "FilledEnd" THEN test26Passed = 0

IF test26Passed = 1 THEN
  PRINT "   [SUCCESS] Empty array strings concatenated safely"
ELSE
  PRINT "   [FAILURE] Empty array strings or array bounds were corrupted"
  PRINT "   Expected UBound: 3"
  PRINT "   Actual UBound:   "; UBOUND(test26Array)
  PRINT "   Expected result: FilledEnd"
  PRINT "   Actual result:   "; test26Combine
END IF

PRINT ""

PRINT "27. Testing Large String Reallocation..."

test27Passed = 1

test27Long = "A"

FOR test27Iteration = 1 TO 10
  test27Long = test27Long + test27Long
NEXT

IF LEN(test27Long) <> 1024 THEN test27Passed = 0
IF MID$(test27Long, 1, 1) <> "A" THEN test27Passed = 0
IF MID$(test27Long, 512, 1) <> "A" THEN test27Passed = 0
IF MID$(test27Long, 1024, 1) <> "A" THEN test27Passed = 0

IF test27Passed = 1 THEN
  PRINT "   [SUCCESS] Large string expanded safely"
ELSE
  PRINT "   [FAILURE] Large string expansion failed or corrupted its payload"
  PRINT "   Expected length: 1024"
  PRINT "   Actual length:   "; LEN(test27Long)
END IF

PRINT ""

pauseForNextPage

PRINT "28. Testing CHR$ and ASC Identity Loop..."

test28Passed = 1
test28FailureAt = 0
test28FailureValue = 0

FOR test28Index = 65 TO 90
  test28Character = CHR$(test28Index)
  test28Value = ASC(test28Character)

  IF test28Value <> test28Index THEN
    test28Passed = 0

    IF test28FailureAt = 0 THEN
      test28FailureAt = test28Index
      test28FailureValue = test28Value
    END IF
  END IF
NEXT

IF test28Passed = 1 THEN
  PRINT "   [SUCCESS] CHR$ and ASC matched correctly"
ELSE
  PRINT "   [FAILURE] CHR$ or ASC returned an incorrect value"
  PRINT "   First failing input: "; test28FailureAt
  PRINT "   Returned value:      "; test28FailureValue
END IF

PRINT ""

PRINT "29. Testing Copy-Out Overwrite Protection..."

test29Passed = 1

test29Variable = "Target"
test29Return = modifyAndReturn$(test29Variable)

IF test29Variable <> "Target Mutated" THEN test29Passed = 0
IF test29Return <> "Target Mutated Returned" THEN test29Passed = 0

IF test29Passed = 1 THEN
  PRINT "   [SUCCESS] Both BYREF copy-out and FUNCTION return succeeded"
ELSE
  PRINT "   [FAILURE] Copy-out and function-return storage collided"
  PRINT "   Expected target: Target Mutated"
  PRINT "   Actual target:   "; test29Variable
  PRINT "   Expected return: Target Mutated Returned"
  PRINT "   Actual return:   "; test29Return
END IF

PRINT ""

PRINT "30. Testing Array of UDTs String Re-assignment..."

test30Passed = 1

parentArray(0).MainMessage = "First Pass"
parentArray(0).InnerData.NestedMessage = "First Inner"

parentArray(2).MainMessage = "Guard Parent"
parentArray(2).InnerData.NestedMessage = "Guard Child"

parentArray(0).MainMessage = "Second Pass"
parentArray(0).MainMessage = parentArray(0).MainMessage + " Complete"

parentArray(0).InnerData.NestedMessage = "Second Inner"
parentArray(0).InnerData.NestedMessage = parentArray(0).InnerData.NestedMessage + " Complete"

IF parentArray(0).MainMessage <> "Second Pass Complete" THEN test30Passed = 0
IF parentArray(0).InnerData.NestedMessage <> "Second Inner Complete" THEN test30Passed = 0
IF parentArray(2).MainMessage <> "Guard Parent" THEN test30Passed = 0
IF parentArray(2).InnerData.NestedMessage <> "Guard Child" THEN test30Passed = 0

IF test30Passed = 1 THEN
  PRINT "   [SUCCESS] UDT array strings reassigned without corrupting adjacent elements"
ELSE
  PRINT "   [FAILURE] UDT array string reassignment leaked or corrupted storage"
  PRINT "   Element 0 parent: "; parentArray(0).MainMessage
  PRINT "   Element 0 child:  "; parentArray(0).InnerData.NestedMessage
  PRINT "   Element 2 parent: "; parentArray(2).MainMessage
  PRINT "   Element 2 child:  "; parentArray(2).InnerData.NestedMessage
END IF

PRINT ""

PRINT "31. Testing Writable Two-Argument ASC..."

test31Passed = 1
test31Text = SPACE$(1)

ASC(test31Text, 1) = 65

test31Value = ASC(test31Text, 1)

IF test31Text <> "A" THEN test31Passed = 0
IF test31Value <> 65 THEN test31Passed = 0

IF test31Passed = 1 THEN
  PRINT "   [SUCCESS] ASC assignment modified the original string"
ELSE
  PRINT "   [FAILURE] ASC assignment did not modify the original string"
  PRINT "   Expected character: [A]"
  PRINT "   Actual character:   ["; test31Text; "]"
  PRINT "   Expected byte value: 65"
  PRINT "   Actual byte value:  "; test31Value
END IF

PRINT ""

PRINT "End of tests."

END

FUNCTION buildRecursiveString$ (depth AS INTEGER) ' Used in test 20
  localPiece$ = CHR$(64 + depth)

  IF depth <= 1 THEN
    buildRecursiveString$ = localPiece$
    EXIT FUNCTION
  END IF

  buildRecursiveString$ = localPiece$ + buildRecursiveString$(depth - 1)
END FUNCTION ' buildRecursiveString$

''''''''''''''''''''''''

FUNCTION buildStringResult$ (text AS STRING, number AS INTEGER) ' Used in tests 10 and 23
  localText$ = "<" + text + ":" + LTRIM$(STR$(number)) + ">"
  buildStringResult$ = localText$
END FUNCTION ' buildStringResult$

''''''''''''''''''''''''

SUB captureComputedArrayValue (value AS LONG) ' Used in test 6
  ' This SUB deliberately does not modify value.
  '
  ' The caller passed a computed expression, so there must not be any
  ' copy-out into expressionSource() after this SUB returns.

  expressionObserved(expressionCallIndex) = value
  expressionCallIndex = expressionCallIndex + 1
END SUB ' captureComputedArrayValue

''''''''''''''''''''''''

FUNCTION combineStringResults$ (leftText AS STRING, rightText AS STRING) ' Used in test 10
  combineStringResults$ = leftText + "|" + rightText
END FUNCTION ' combineStringResults$

''''''''''''''''''''''''

SUB earlyCopyOut (text AS STRING, mode AS INTEGER) ' Used in test 14
  text = "Early Exit Copy-Out"

  IF mode = 1 THEN
    EXIT SUB
  END IF

  text = "Late Copy-Out"
END SUB ' earlyCopyOut

''''''''''''''''''''''''

FUNCTION earlyStringResult$ (mode AS INTEGER) ' Used in test 14
  localText$ = "Local Temporary"

  IF mode = 1 THEN
    earlyStringResult$ = "Early Return"
    EXIT FUNCTION
  END IF

  localText$ = localText$ + " Preserved"

  IF localText$ = "Local Temporary Preserved" THEN
    earlyStringResult$ = "Late Return"
  ELSE
    earlyStringResult$ = "Corrupt Local"
  END IF
END FUNCTION ' earlyStringResult$

''''''''''''''''''''''''

FUNCTION incrementAndReturn (value AS INTEGER) ' Used in test 18
  value = value + 5
  incrementAndReturn = value * 10
END FUNCTION ' incrementAndReturn

''''''''''''''''''''''''

FUNCTION layerOne$ (iteration AS LONG) ' Used in test 21
  layerOne$ = layerTwo$(iteration) + "A"
END FUNCTION ' layerOne$

''''''''''''''''''''''''

FUNCTION layerThree$ (iteration AS LONG) ' Used in test 21
  layerThree$ = "C"
END FUNCTION ' layerThree$

''''''''''''''''''''''''

FUNCTION layerTwo$ (iteration AS LONG) ' Used in test 21
  layerTwo$ = layerThree$(iteration) + "B"
END FUNCTION ' layerTwo$

''''''''''''''''''''''''

FUNCTION localArrayProbe$ (seed AS INTEGER) ' Used in test 17
  REDIM localParts(2) AS STRING

  localParts(0) = "A" + LTRIM$(STR$(seed))
  localParts(1) = "B" + LTRIM$(STR$(seed + 1))
  localParts(2) = "C" + LTRIM$(STR$(seed + 2))

  localArrayProbe$ = localParts(0) + "|" + localParts(1) + "|" + localParts(2)
END FUNCTION ' localArrayProbe$

''''''''''''''''''''''''

SUB modifyAliasedNumeric (firstValue AS INTEGER, secondValue AS INTEGER) ' Used in test 9
  firstValue = firstValue + 3
  secondValue = firstValue * 2
END SUB ' modifyAliasedNumeric

''''''''''''''''''''''''

SUB modifyAliasedString (firstText AS STRING, secondText AS STRING) ' Used in test 9
  firstText = firstText + "A"
  secondText = firstText + "B"
END SUB ' modifyAliasedString

''''''''''''''''''''''''

FUNCTION modifyAndReturn$ (targetVar AS STRING) ' Used in test 29
  targetVar = targetVar + " Mutated"
  modifyAndReturn$ = targetVar + " Returned"
END FUNCTION ' modifyAndReturn$

''''''''''''''''''''''''

SUB modifyArray (element AS STRING) ' Used in test 1
  ' If Copy-Out fails, this change will be discarded
  element = "Modified Array Data Successfully!"
END SUB ' modifyArray

''''''''''''''''''''''''

SUB modifyBoundedMatrix (arr() AS LONG) ' Used in test 11
  arr(2, 5) = 125
  arr(4, 7) = 447
  arr(3, 6) = arr(2, 5) + arr(4, 7)
END SUB ' modifyBoundedMatrix

''''''''''''''''''''''''

SUB modifyDirectUdt (struct AS ParentStruct) ' Used in test 3
  ' If Direct UDTs are trapped as BYVAL, this change will be discarded
  struct.InnerData.NestedValue = 999
END SUB ' modifyDirectUdt

''''''''''''''''''''''''

SUB modifyEightArguments (arg1 AS INTEGER, arg2 AS LONG, arg3 AS STRING, arg4 AS INTEGER, arg5 AS STRING, arg6 AS LONG, arg7 AS INTEGER, arg8 AS STRING) ' Used in test 8
  arg1 = 11
  arg2 = 22
  arg3 = arg3 + " Modified"
  arg4 = 44
  arg5 = arg5 + " Modified"
  arg6 = 66
  arg7 = 77
  arg8 = arg8 + " Modified"
END SUB ' modifyEightArguments

''''''''''''''''''''''''

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

''''''''''''''''''''''''

SUB modifyUdtArrayElement (struct AS ParentStruct) ' Used in test 12
  struct.MainMessage = "Modified Array Parent"
  struct.MainValue = 111
  struct.InnerData.NestedMessage = "Modified Array Child"
  struct.InnerData.NestedValue = 222
END SUB ' modifyUdtArrayElement

''''''''''''''''''''''''

SUB modifyUdtField (targetStr AS STRING) ' Used in test 2
  ' If Copy-Out fails, this change will be discarded
  targetStr = "Modified Nested UDT Data Successfully!"
END SUB ' modifyUdtField

''''''''''''''''''''''''

SUB modifyWholeArray (arr() AS STRING) ' Used in test 4
  ' If the array descriptor is not copied back, the caller may retain the old array
  REDIM arr(15) AS STRING
  arr(1) = "After REDIM"
END SUB ' modifyWholeArray

''''''''''''''''''''''''

SUB pauseForNextPage
  DO
    keyPress$ = INKEY$
  LOOP WHILE keyPress$ <> ""

  PRINT "Press any key to continue..."

  DO
    keyPress$ = INKEY$
  LOOP UNTIL keyPress$ <> ""

  CLS
END SUB ' pauseForNextPage

''''''''''''''''''''''''

FUNCTION resizeArrayAndReturn (arr() AS STRING) ' Used in test 19
  REDIM arr(9) AS STRING
  arr(9) = "Function Resize"
  resizeArrayAndReturn = UBOUND(arr)
END FUNCTION ' resizeArrayAndReturn

