Code highlighter test
===============================================================================

Verification scenarios for server-side syntax highlighting via JavaScriptCore.


## Known languages

### Swift

```swift
import Foundation

struct Greeter {
    let name: String

    func greet() -> String {
        return "Hello, \(name)!"
    }
}

let g = Greeter(name: "world")
print(g.greet())
```


### Python

```python
from dataclasses import dataclass

@dataclass
class Point:
    x: float
    y: float

    def distance(self) -> float:
        return (self.x ** 2 + self.y ** 2) ** 0.5

points = [Point(3, 4), Point(0, 0)]
for p in points:
    print(f"{p} -> {p.distance():.2f}")
```


### JavaScript

```javascript
async function fetchUsers(ids) {
  const results = await Promise.all(
    ids.map(id => fetch(`/api/users/${id}`).then(r => r.json()))
  );
  return results.filter(u => u.active === true);
}

fetchUsers([1, 2, 3]).then(users => console.log(users));
```


### Ruby

```ruby
class Invoice
  attr_reader :items

  def initialize
    @items = []
  end

  def add(description, amount)
    @items << { description:, amount: }
    self
  end

  def total
    @items.sum { |i| i[:amount] }
  end
end
```


## Unknown language (should fall back to `highlightAuto`)

```foobar
DECLARE @x INT = 42;
IF @x > 0 THEN
  PRINT 'positive';
END IF;
```


## No language (should use `highlightAuto`)

```
for i in range(10):
    print(i)
```


## Indented code block (no fence, no language)

    SELECT id, name
    FROM users
    WHERE active = 1
    ORDER BY name;


## HTML entities (must not double-escape)

```html
<div class="container">
  <p>Tom &amp; Jerry</p>
  <img src="logo.png" alt="A &quot;great&quot; logo" />
  <script>alert("xss");</script>
</div>
```

```swift
let a = 1 < 2
let b = "quotes: \"hello\""
let c = "ampersand: &"
let d = "<div class=\"test\">&amp;</div>"
```


## Edge cases

### Empty code block

```swift

```


### Single-line code block

```python
x = 42
```


### Code with only whitespace

```javascript

```


### Very long line

```rust
fn main() { let very_long_variable_name_that_goes_on_and_on_and_on_and_on: Vec<Result<HashMap<String, Vec<Option<Box<dyn Iterator<Item = Result<String, Error>>>>>>, Error>> = Vec::new(); }
```

-------------------------------------------------------------------------------
