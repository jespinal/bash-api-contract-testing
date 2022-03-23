# Bash API Contract Testing

This is a proof of concept (POC) tool used for API contract testing as a way to ensure that, given any number of API endpoints, a request `R` returns a proper response `RP` no matter what have been chaged at the endpoint side. Basically we wanted a way to get sure that the external contract of an endpoint is preserved even if we rewrite the whole thing in different language.

While this is shared for educational purposes, it can actually be used in real scenarios where you need to evaluate the structure of responses, and the nature of its elements.

Additionally, you can derive your own solutions and/or use is as reference on how to glue a few command line tools using bash scripting.

### As part of the main requirements, we have:

* Whatever is used should not be language specific (PHP, Typescript, etc).
    - If we can get by with curl/httpie, Makefiles, and shell scripts, that would keep this test suite portable should we ever change what the microservice is running on (Lambda vs something else).
* Testing can be done against the service deployed in AWS or wherever we have it.
    - Note: for microservices that are not Lambda based, we’d just spin up a Docker container listening on the correct port and submit HTTP requests to it

### How does it works?

All the functionality is contained in a simple _main.sh_ script. For clarity's sake, most of the implementation details was extracted into functions which reside in the _functions.sh_ file. So by simply looking at _main.sh_ file you have an idea of how everything works. If you need more details, you can go into each particular function implementation.

So a summary of the whole logic can be stated as: 

Look for all _rules_ files inside the `rules/` directory, and for each one send a request (`R`) to the configured endpoint (depending on the environment), and evaluate the response (`RP`) according to **how** the _rules_ file says it should look like. The body of the request is called a _fixture_, and is located inside the `rules/fixtures/` directory under the same name as the _rules_ file, but with a `.json` extension (the _rules_ file uses `.rlz`).

That's it.

### How does the tool knows where to send the request?

That is configured in the `.env` file, which has minimal settings to be changed. You'd just need to copy `env.dist` to `.env` and adjust it.

### How does the tool knows what HTTP method to use and what endpoint to hit?

The name of the _rules_ file determines the HTTP method to be used and the endpoint to be hit. For instance, consider the following rules/fixture file names:

```
post.payment.capture.001-success.rlz
post.payment.capture.001-success.json
```

In other words:

```
\[HTTP method].\[module name or category].\[endpoint name].\[unique identifier separated by hyphens '-'].rlz
```

The second segment ("module name or category") is used for infomational purposes only.

Based on that _rules_ file the tool will be sending the content of the _fixture_ file to the `capture` endpoint of the URL configured in the `.env` file. For this, the HTTP `POST` method will be used. Whatever we receive as a response will then be evaluated according to the definitions of the `rules` file.


### An Introducton to the _rules_ files syntax

Basically, a _rules_ files is a set of entries compound of **4 elements** separated by tabs (`\t`). I repeat, tabs, not spaces, not 2 or 4 spaces, not whatever-invisible-character might exist in the utf8 universe, but actual tabs: `\t`, and finished with semicolon (`;`), which is **required** too.

So, the 4 elements are:

1. A `jq`¹ filter **or** (that's what we mean by "|") the name of a `callback` function preceded with the `callback_` keyword.
2. The name of an `assertion`² to be invoked.
3. The expected value against which the assertion will be processed.
4. An optional (but quite useful) comment line.

E.g.

```
# jq filter|callback_your_callback_name<\t>assertion name<\t>expected value<\t>[optional comment]<;>
```

Here's an example response (`RP`) and a commented rules file which can be used to evaluate it:

```
{
  "code": 200,
  "data": {
    "transaction": {
      "id": "string",
      "status": "completed"
    }
  }
}
```

```
#
# Evaluating the structure of the response.
#
# Note: the jq builtin function `has()` returns whether the input object has the given key,
# or the input array has an element at the given index
#
# Format:
# jq filter|callback_your_callback_name<\t>assertion name<\t>expected value<\t>[optional comment]<;>
has("code")	equals	true	"'code' element is present";
has("data")	equals	true	"'data' element is present";
.data|has("transaction")	equals	true	"'data' element has a 'transaction' child";
.data.transaction|has("id")	equals	true	"'transaction' has an 'id' child'";
.data.transaction|has("status")	equals	true	"'transaction' has a 'status' child'";

# Code element included in the JSON body should be 200
# Note: this can also be stated as
# .code	equals	200;
.code == 200	equals	true	"code value must be 200";

# Data element should be an object
.data|type	equals	"object"	"'data' must be of type 'object'";

# Transaction element should be an object
.data.transaction|type	equals	"object"	"'transaction' must be of type 'object'";

# Id element should be a string
.data.transaction.id|type	equals	"string"	"'id' element should be a string";

# Status element should be a string
.data.transaction.status|type	equals	"string"	"'status' element should be a string";

# Status should be either "completed" or "failed"
.data.transaction.status == "completed" or .data.transaction.status == "failed"	equals	true	"'status' field should be one of: 'completed', 'failed'";

# Finally, this is how a callback should be called.
# In a callback, some mysterious logic that is not part of the main tool
# can be developed before we actually need (if we ever do) to modify the
# tool itself
callback_return_status_code	equals	200	"the response status code should be 200"
```

It looks a bit convoluted. But that's just because for us it's not possible to visually tell appart tabs (`\t`) from spaces, so it looks like a big mess. But for the sake of this writting, let's take some rules and change `\t` characters for something we can see:

```
has("code") <--|TAB|--> equals <--|TAB|--> true <--|TAB|--> "'code' element is present";
has("data") <--|TAB|--> equals <--|TAB|--> true <--|TAB|--> "'data' element is present";
.data|has("transaction") <--|TAB|--> equals <--|TAB|--> true <--|TAB|--> "'data' element has a 'transaction' child";
.data.transaction|has("id") <--|TAB|--> equals <--|TAB|--> true <--|TAB|--> "'transaction' has an 'id' child'";
.data.transaction|has("status") <--|TAB|--> equals <--|TAB|--> true <--|TAB|--> "'transaction' has a 'status' child'";
```

There you go.

As you can see, the complexity is gone. All that remains are elements cleraly identifiables. E.g.:

```
has("code") <--|TAB|--> equals <--|TAB|--> true <--|TAB|--> "'code' element is present";
```

Here I'm using the builtin `jq` function `has()` as part of the filter (it returns `true` or `false`) to indicate that I expect the result of that evaluation `equals` (name of my assertion) `true`. Then I added a comment which adds clarity when the test runs.

### What are assertions?

Assertions are small functions located in the `assertions/` directory which are used to evaluate the value returned by a given `jq` filter or a callback.

### What's a callback?

A callback is a small (or not so small, it's up to you) function which returns a value in place of a `jq` filter. The returned value will then be evaluated using the provided `assertion`. Callbacks are located in the `callbacks/` directory.
