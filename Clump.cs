using System;

namespace GrassSystem
{
    // 一簇草的参数。每项都是「基准值 + 随机范围」，compute 里逐个草叶算
    [Serializable]
    public struct ClumpParameters
    {
        public float pullToCenter;
        public float alignToCrowd;
        public float heightBase;
        public float heightRange;
        public float widthBase;
        public float widthRange;
        public float tiltBase;
        public float tiltRange;
        public float bendBase;
        public float bendRange;
    }
}