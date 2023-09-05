# powersof2
Search for powers of 2 almost divisible by their exponent.
This program was written in response to https://proofwiki.org/wiki/Smallest_n_for_which_2%5En-3_is_Divisible_by_n

The smallest positive integer n such that 2^n - 3 is divisible by n turns out to be too large to be represented in 32 bits. The present program was written in X86 assembly language (NASM syntax) to exploit the capabilities in 64-bit and 128-bit arithmetic on modern X86-64 processors.

The program is configured to report exponents n for which 2^n is congruent to 7 or 5 or 3 modulo n.

Fortunately, remainders of 7 and 5 seem to occur more frequently than remainders of 3 hence they are a convenient check of the program's operation.

The program gains speed by being small enough to fit easily in the L1 stack and by holding all the relevant information in CPU registers. The registers used were chosen because they are available in Linux; register assignments might need adjustment in other operating systems.

Running native mode in a single thread on an AMD Ryzen 5700G, the program searched exponents up to 10^13 in a couple of weeks. Further searches could be distributed among several machines or threads. However, the program should be checked carefully by someone with more knowledge in the field. The program could theoretically test exponents up to 2^64 - 1 or 18446744073709551615.

More detailed explanations of the program are to be found in comments within the source text.

