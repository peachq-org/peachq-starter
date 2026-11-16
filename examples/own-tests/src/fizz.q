.fizz.word:{$[0=x mod 15;"FizzBuzz";0=x mod 3;"Fizz";0=x mod 5;"Buzz";string x]};
.fizz.upto:{.fizz.word each 1+til x};
