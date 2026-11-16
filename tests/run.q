\l tests/qunit.q
\l src/math.q
\l tests/mathTest.q
r:.qunit.runTests `.mathTest;
.qunit.saveJUnit[`:junit.xml; r];
/ on peachq, peachq-known-gaps.txt lists tests expected to fail; a listed test that passes fails the run too
gaps:$[(10h=type @[value;`.pq.version;0]) and not ()~key f:hsym `$"peachq-known-gaps.txt";
  `$first each " " vs/: l where not (l:trim read0 f) like "#*"; `$()] except `;
fails:exec name from r where not status in `pass`skip;
if[count u:fails except gaps; -2 "failed: "," " sv string u];
if[count p:gaps except fails; -2 "now pass, remove from peachq-known-gaps.txt: "," " sv string p];
exit $[count[u]+count p; 1; 0];
