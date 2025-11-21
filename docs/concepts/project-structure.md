# Project Structure

Organizing DS01 projects for collaboration and reproducibility.

## Recommended Structure

```
my-project/
├── README.md
├── requirements.txt
├── .gitignore
├── data/
│   ├── raw/
│   └── processed/
├── notebooks/
├── src/
│   ├── __init__.py
│   ├── data.py
│   ├── model.py
│   └── train.py
├── models/
├── results/
└── tests/
```

## Essential Files

**README.md** - Project documentation
**requirements.txt** - Python dependencies
**.gitignore** - Exclude data/models from Git
**src/** - Reusable source code

## Best Practices

1. **Separate code from data**
2. **Use version control** (Git)
3. **Document setup steps**
4. **Include example usage**
5. **Test your code**

## Next Steps

→ [Creating Projects](../workflows/creating-projects.md)
→ [Collaboration](../workflows/collaboration.md)
