import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

// Practice screens only: a top with one button, a month list that is empty this month, one record a month back.
export default function List() {
  const [view, setView] = useState<'top' | 'month' | 'one'>('top');
  const [back, setBack] = useState(0);
  if (view === 'top') {
    return (
      <View style={styles.root}>
        <Pressable accessibilityRole="button" style={styles.btn} onPress={() => setView('month')}>
          <Text style={styles.btnText}>記録の一覧</Text>
        </Pressable>
      </View>
    );
  }
  if (view === 'one') {
    return (
      <View style={styles.root}>
        <Text style={styles.title}>記録の中身</Text>
        <Text>2 images (practice)</Text>
        <Pressable accessibilityRole="button" accessibilityLabel="閉じる" style={styles.btn} onPress={() => setView('month')}>
          <Text>閉じる</Text>
        </Pressable>
      </View>
    );
  }
  return (
    <View style={styles.root}>
      <Text style={styles.title}>月をえらぶ</Text>
      <Text>{back === 0 ? 'this month' : `${back} month(s) back`}</Text>
      <Pressable accessibilityRole="button" style={styles.btn} onPress={() => setBack(back + 1)}>
        <Text style={styles.btnText}>前の月</Text>
      </Pressable>
      {back >= 1 ? (
        <Pressable accessibilityRole="button" accessibilityLabel="1日の記録（画像2枚）を開く" style={styles.btn} onPress={() => setView('one')}>
          <Text style={styles.btnText}>1日の記録</Text>
        </Pressable>
      ) : (
        <Text>no records</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 16, backgroundColor: '#fff' },
  title: { fontSize: 24 },
  btn: { minHeight: 44, minWidth: 160, paddingHorizontal: 20, alignItems: 'center', justifyContent: 'center', borderRadius: 8, backgroundColor: '#e8eef8' },
  btnText: { fontSize: 18 },
});
