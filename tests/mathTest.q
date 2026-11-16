system "d .mathTest";
testClamp:{.qunit.assertEquals[.math.clamp[0;10;-5 5 15]; 0 5 10; "clamps both ends"]};
testMid:{.qunit.assertEquals[.math.mid 1 9 4; 5f; "midpoint of the range"]};
testFactorial:{.qunit.assertEquals[.math.factorial 5; 120; "5!"]};
testFactorialNegative:{.qunit.assertError[.math.factorial; -1; "negative is refused"]};
