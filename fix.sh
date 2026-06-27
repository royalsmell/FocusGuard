#!/bin/bash
find . -name "*.swift" -exec sed -i '' 's/apiKey: \*\*\*/apiKey: String?/g' {} +
find . -name "*.swift" -exec sed -i '' 's/apiKey: \*\*\*/apiKey: String?/g' {} +
