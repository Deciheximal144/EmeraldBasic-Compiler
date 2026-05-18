Simplest-No-Contingency-BASIC-Compiler, too early for versions

A public domain compiler for an incredibly simple BASIC language that has few features. Designed as a way that you can make your own language in QBASIC 64 Phoenix Edition without having to deal with libraries.

It has one file that goes with it, "SIMPLEGRAPHICS.bmp", for a slightly different palette, in the same folder as the project. The file for the in compiler text is called CODE.txt. A sample is included in that file.

Zero rights claimed, use it to take over the world for all I care. AI helped make this project, so I couldn't claim them anyway. Intellectual property can go take a walk.

Now, here's what the AI made up for the readme for current features:

The compiler itself provides a simple integrated development environment (IDE) where you can write and edit your BASIC code. It then performs all the steps of compilation—from tokenizing the source to generating x86-64 machine code and building the final .exe file from scratch.

How to Use
1. Load and run CmpBasic.bas in QB64PE.
2. Write your BASIC code in the editor window that appears.
3. Press the F5 key to compile your code.
4. The output file, named Output.exe by default, will be created in the same directory.


Supported Features

General
*   Variable assignment using =. The LET keyword is not supported.
*   Numeric and string variables. String variable names must end with a $ character.
*   Variable names are limited to 64 characters.
*   DIM to declare variables and arrays of specific types. Supported types include LONG, _BYTE, _INTEGER64, and their _UNSIGNED versions.
*   SUB and FUNCTION for creating procedures, with support for arguments.
*   CALL (or implicit call) to execute procedures.
*   CONST for defining text-based constants.

Control Flow
*   IF / THEN / ELSE / END IF with conditions: =, <, >, <=, >=, <>.
*   FOR / TO / STEP / NEXT loops.
*   DO / LOOP with optional WHILE or UNTIL conditions.
*   GOTO with alphanumeric or numeric labels.
*   SELECT CASE / CASE / END SELECT.

Console I/O
*   PRINT to display text and numbers. Use a semicolon (;) or comma (,) to suppress the newline.
*   INPUT to get user input from the console.
*   CLS to clear the console screen.
*   LOCATE to position the text cursor.
*   COLOR to set foreground and background text colors.
*   INKEY$ and INKEYF$ for non-blocking keyboard input.

Built-in Functions
*   String Functions: CHR$, LEN, UCASE$, MID$, LTRIM$, RTRIM$, STR$.
*   Data Type Functions: ASC, VAL.

Graphics Mode
*   Enable by adding GRAPHICS at the beginning of your code.
*   Syntax: GRAPHICS [width, height], "WindowTitle"
*   Default window size is 640x480.
*   PSET X, Y, color to draw a single pixel.
*   LINE (x1, y1)-(x2, y2), color, [B|BF] to draw lines and boxes.
*   GET (x1, y1)-(x2, y2), arrayName to capture a screen area into an array.
*   PUT (x, y), arrayName to draw a captured image from an array.
*   CLS clears the graphics screen.
*   LOCATE positions the text cursor for PRINT statements in the graphics window.

Compiler Directives
*   GRAPHICS: Enables graphics mode. Must be at the top of the file.
*   #GDOUBLE: Doubles the size of the graphics window for display (2x scaling).
*   #LOCATE1: Switches LOCATE coordinates to be 1-based instead of 0-based.