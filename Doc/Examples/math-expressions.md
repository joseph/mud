Math expressions
===============================================================================

Mud renders TeX math the same way GitHub does, using the same delimiter forms.
Each expression is converted to MathML when the document renders and drawn
natively by the browser — no MathJax, no client-side JavaScript, and nothing
extra baked into an exported document.


## Fenced math blocks

A fenced block tagged `math` renders as a centered, display-size equation.
Because the content sits inside a code fence, every TeX character is safe, so
this is the most reliable way to write anything with backslashes, ampersands,
or long macros.

The Gaussian integral:

```math
\int_{-\infty}^{\infty} e^{-x^2}\, dx = \sqrt{\pi}
```

The Basel problem:

```math
\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}
```

A matrix–vector product:

```math
\begin{bmatrix} a & b \\ c & d \end{bmatrix}
\begin{bmatrix} x \\ y \end{bmatrix}
=
\begin{bmatrix} ax + by \\ cx + dy \end{bmatrix}
```

A piecewise definition:

```math
\operatorname{sgn}(x) =
\begin{cases}
  -1 & \text{if } x < 0 \\
   0 & \text{if } x = 0 \\
   1 & \text{if } x > 0
\end{cases}
```

Aligned derivation:

```math
\begin{aligned}
  (a + b)^2 &= a^2 + 2ab + b^2 \\
  (a - b)^2 &= a^2 - 2ab + b^2
\end{aligned}
```


## Display math

A paragraph fenced by `$$` on both ends is display math too. Subscripts survive
intact — the underscores below stay subscripts and do not become emphasis:

$$ a_1 x_1 + a_2 x_2 + \dots + a_n x_n = \mathbf{b} $$

$$ x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a} $$


## Inline math

Wrap an expression in `` $`…`$ `` to set it inline with the surrounding text.
The area of a circle of radius $`r`$ is $`\pi r^2`$, and Euler's identity
$`e^{i\pi} + 1 = 0`$ ties together five constants at once. The golden ratio
$`\varphi = \tfrac{1 + \sqrt{5}}{2}`$ satisfies $`\varphi^2 = \varphi + 1`$.

The backticks protect the expression from Markdown, so underscores and
backslashes inside the math are always safe.


## Coverage samples

Greek letters, operators, and relations all render:

```math
\alpha + \beta \geq \gamma \qquad
\nabla \times \mathbf{B} = \mu_0 \mathbf{J}
  + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
```

Fractions, roots, and limits nest cleanly:

```math
\lim_{x \to 0} \frac{\sin x}{x} = 1 \qquad
\sqrt[3]{\frac{27}{8}} = \frac{3}{2}
```


## What is not math

These cases must render as ordinary text, not equations. Prices in prose keep
their dollar signs: a coffee is $3 and a refill is $2, so the round comes to
$5. A bare `$…$` pair is deliberately **not** treated as math — writing $x + y$
here leaves the dollar signs on the page, exactly as typed. Reach for the
`` $`…`$ `` form when you want $`x + y`$ to render instead.


## Math in a footnote

Footnotes carry math too. The harmonic series diverges,[^1] which still
surprises people.

[^1]: That is, $`\sum_{n=1}^{\infty} \frac{1}{n}`$ grows without bound.


## Invalid input

Malformed TeX does not break the page — the offending source is shown in place
as an error, matching GitHub's behavior:

```math
\frac{1}{\notARealCommand
```


-------------------------------------------------------------------------------
