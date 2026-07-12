import marimo

__generated_with = "0.23.14"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo

    return (mo,)


@app.cell
def _(mo):
    count = mo.ui.slider(1, 10, value=3, label="Evidence count")
    count
    return (count,)


@app.cell
def _(count, mo):
    mo.md(f"**Local result:** {count.value * 2}")
    return


if __name__ == "__main__":
    app.run()
