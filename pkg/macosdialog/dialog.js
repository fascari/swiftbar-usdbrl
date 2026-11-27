let dialog;

function run() {
    // JXA provides Application at runtime.
    //noinspection JSUnresolvedReference
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;
    if (dialog.choices !== null) {
        const selected = app.chooseFromList(dialog.choices, {
            withTitle: dialog.title,
            withPrompt: dialog.message,
        });
        return selected ? selected[0] : "";
    }
    const options = {withTitle: dialog.title};
    if (dialog.answer !== null) options.defaultAnswer = dialog.answer;
    const result = app.displayDialog(dialog.message, options);
    // JXA supplies the dialog result properties.
    //noinspection JSUnresolvedReference
    return result.textReturned || "";
}
