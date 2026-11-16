/ A self-contained test script: qci reads only its exit code, 0 for pass.
\l src/fizz.q
fails:0;
check:{[name;got;want] if[not got~want; -2 "FAIL ",name,": got ",(-3!got),", want ",-3!want; fails::fails+1]};
check["one"; .fizz.word 1; enlist "1"];
check["fizz"; .fizz.word 9; "Fizz"];
check["buzz"; .fizz.word 10; "Buzz"];
check["fizzbuzz"; .fizz.word 30; "FizzBuzz"];
check["upto"; .fizz.upto 5; (enlist "1";enlist "2";"Fizz";enlist "4";"Buzz")];
-1 string[fails]," failure(s)";
exit $[fails;1;0];
