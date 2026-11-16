\l tests/qunit.q
\l src/math.q
\l tests/mathTest.q
r:.qunit.runTests `.mathTest;
.qunit.saveJUnit[`:junit.xml; r];
fails:exec name from r where not status in `pass`skip;
if[count fails; -2 "failed: "," " sv string fails];
exit `int$0<count fails;
