/ Runs the qunit tests, writes qci-junit.xml for per-test results, and exits 1 unless every test passed or was skipped.
\l qunit.q
\l src/math.q
\l tests/mathTest.q
r:.qunit.runTests `.mathTest;

esc:{ssr/[x;enlist each "&<>\"";("&amp;";"&lt;";"&gt;";"&quot;")]};
str:{$[10h=type x;x;-3!x]};
case:{[t]
  s:t`status;
  a:"<testcase classname=\"",esc[string t`namespace],"\" name=\"",esc[string last ` vs t`name],"\"";
  if[s in `pass`skip; :a,$[`pass=s;"/>";"><skipped/></testcase>"]];
  m:$[`fail=s; str[t`msg],": expected ",(-3!t`expected),", got ",-3!t`actual; str t`result];
  a,"><",$[`fail=s;"failure";"error"]," message=\"",esc[m],"\"/></testcase>"};
xml:("<?xml version=\"1.0\" encoding=\"UTF-8\"?>";"<testsuite name=\"qunit\" tests=\"",string[count r],"\">"),(case each r),enlist "</testsuite>";
(hsym `$"qci-junit.xml") 0: xml;
exit $[all r[`status] in `pass`skip;0;1];
