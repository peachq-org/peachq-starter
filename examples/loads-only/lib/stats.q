/ Small statistics helpers. This example has no tests: qci checks only that the library loads.
.stats.zscore:{(x-avg x)%dev x};
.stats.wavg:{[w;x] (sum w*x)%sum w};
.stats.ema:{[a;x] {[a;p;c] (a*c)+(1-a)*p}[a]\[x]};
.stats.summary:{`n`mean`sd`min`max!(count x;avg x;dev x;min x;max x)};
