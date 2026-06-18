/// 书架排序方式
enum LibrarySortType
{
    /// 最近添加
    addedAtDesc,

    /// 最近阅读
    lastReadDesc,

    /// 标题 A→Z
    titleAsc,

    /// 占用空间 大→小
    sizeDesc,
}

/// 书架排序方式扩展
extension LibrarySortTypeX on LibrarySortType
{
    /// 列表中的展示标题
    String get label
    {
        switch (this)
        {
            case LibrarySortType.addedAtDesc:
                return '最近添加';
            case LibrarySortType.lastReadDesc:
                return '最近阅读';
            case LibrarySortType.titleAsc:
                return '标题';
            case LibrarySortType.sizeDesc:
                return '占用空间';
        }
    }
}
