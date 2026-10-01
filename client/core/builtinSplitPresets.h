#ifndef BUILTINSPLITPRESETS_H
#define BUILTINSPLITPRESETS_H

#include <QJsonArray>

namespace BuiltinSplitPresets
{
    QJsonArray presets();
    QJsonArray mergeWithApi(const QJsonArray &apiPresets);
}

#endif
