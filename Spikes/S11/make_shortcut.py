"""Writes the unsigned `FocusDock Set Focus` Shortcut plist for spike S11.

Input: a Focus name, or `Off`. The Focus parameter of Set Focus is bound to Shortcut Input,
which is exactly what S11 tests. The Shortcut outputs the current Focus afterwards so
`shortcuts run ... -o` can verify the effect without reading Focus state elsewhere.
Usage: python3 make_shortcut.py unsigned.shortcut  then  shortcuts sign --mode anyone -i unsigned.shortcut -o "FocusDock Set Focus.shortcut"
(the sign command rejects inputs without the .shortcut extension).
"""
import plistlib
import sys
import uuid

INPUT = {"Value": {"Type": "ExtensionInput"}, "WFSerializationType": "WFTextTokenAttachment"}


def output_of(action_uuid, name):
    return {"Value": {"Type": "ActionOutput", "OutputUUID": action_uuid, "OutputName": name},
            "WFSerializationType": "WFTextTokenAttachment"}


def action(ident, **params):
    return {"WFWorkflowActionIdentifier": ident, "WFWorkflowActionParameters": params}


def build():
    group = str(uuid.uuid4()).upper()
    cur_off, cur_end = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
    actions = [
        action("is.workflow.actions.conditional", GroupingIdentifier=group, WFControlFlowMode=0,
               WFCondition=4, WFConditionalActionString="Off",
               WFInput={"Type": "Variable", "Variable": INPUT}),
        action("is.workflow.actions.dnd.getfocus", UUID=cur_off),
        action("is.workflow.actions.dnd.set", Enabled=0, FocusModes=output_of(cur_off, "Focus")),
        action("is.workflow.actions.conditional", GroupingIdentifier=group, WFControlFlowMode=1),
        action("is.workflow.actions.dnd.set", Enabled=1, AssertionType="Turned Off", FocusModes=INPUT),
        action("is.workflow.actions.conditional", GroupingIdentifier=group, WFControlFlowMode=2),
        action("is.workflow.actions.dnd.getfocus", UUID=cur_end),
        action("is.workflow.actions.output", WFNoOutputSurfaceBehavior="Do Nothing",
               WFOutput={"Value": {"string": "￼",
                                   "attachmentsByRange": {"{0, 1}": {"Type": "ActionOutput", "OutputUUID": cur_end, "OutputName": "Focus"}}},
                         "WFSerializationType": "WFTextTokenString"}),
    ]
    return {
        "WFWorkflowName": "FocusDock Set Focus",
        "WFWorkflowActions": actions,
        "WFWorkflowClientVersion": "3000",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowInputContentItemClasses": ["WFStringContentItem", "WFGenericFileContentItem"],
        "WFWorkflowOutputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowTypes": [],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59511},
    }


if __name__ == "__main__":
    with open(sys.argv[1], "wb") as f:
        plistlib.dump(build(), f, fmt=plistlib.FMT_BINARY)
