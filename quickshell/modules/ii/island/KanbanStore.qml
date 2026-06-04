pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

// Persisted kanban board. Cards are a flat list of { id, text, col } where
// col is 0=To Do, 1=In Progress, 2=Done. Moving a card = changing its col.
// Stored as JSON at <state>/user/kanban.json (same convention as Todo).
Singleton {
    id: root
    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/kanban.json`)
    property var cards: []
    property int nextId: 1
    property int lastId: -1

    function persist() {
        root.cards = root.cards.slice(0); // reassign → notify bindings
        kanbanFile.setText(JSON.stringify({ "nextId": root.nextId, "cards": root.cards }));
    }
    function add(col, text) {
        const id = root.nextId++;
        root.cards.push({ "id": id, "text": text, "col": col });
        root.lastId = id;
        persist();
    }
    function setText(id, text) {
        const c = root.cards.find(c => c.id === id);
        if (c) {
            c.text = text;
            persist();
        }
    }
    function move(id, col) {
        const c = root.cards.find(c => c.id === id);
        if (c && c.col !== col) {
            c.col = col;
            persist();
        }
    }
    function remove(id) {
        root.cards = root.cards.filter(c => c.id !== id);
        persist();
    }
    function cardsIn(col) {
        return root.cards.filter(c => c.col === col);
    }

    Component.onCompleted: kanbanFile.reload()

    FileView {
        id: kanbanFile
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            try {
                const d = JSON.parse(kanbanFile.text());
                root.cards = d.cards ?? [];
                root.nextId = d.nextId ?? 1;
            } catch (e) {
                root.cards = [];
                root.nextId = 1;
            }
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                root.cards = [];
                root.nextId = 1;
                kanbanFile.setText(JSON.stringify({ "nextId": 1, "cards": [] }));
            }
        }
    }
}
