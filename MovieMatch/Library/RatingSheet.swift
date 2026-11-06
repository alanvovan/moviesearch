//
//  RatingSheet.swift
//  MovieMatch
//

import SwiftUI

struct RatingSheet: View {
    var title: String
    var requiresRating: Bool
    var allowsUnrated: Bool
    @State var rating: Int?
    @State var review: String
    var onSave: (Int?, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(0...10, id: \.self) { value in
                            Button(String(value)) { rating = value }
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(rating == value ? .black : .white)
                                .background(rating == value ? Color.white : Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                    TextField("Отзыв, если есть", text: $review, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    Button {
                        guard let rating else { return }
                        onSave(rating, review)
                        dismiss()
                    } label: {
                        Text("Сохранить")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(MovieMatchCapsuleStyle())
                    .disabled(requiresRating && rating == nil)
                    .opacity(requiresRating && rating == nil ? 0.45 : 1)
                    if allowsUnrated {
                        Button("Сохранить без оценки") {
                            onSave(nil, review)
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .movieMatchScreen()
            .navigationTitle("Оценка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationBackground(MovieMatchPalette.background)
        .preferredColorScheme(.dark)
    }
}
