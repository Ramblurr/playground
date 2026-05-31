import java.lang.foreign.Linker;

public class TestFFM {
    public static void main(String[] args) {
        Linker linker = Linker.nativeLinker();
        System.out.println("native linker = " + linker.getClass().getName());
    }
}
